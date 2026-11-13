package Plugins::SBRadio::Plugin;

# Fetches the SBRadio applet repository (extensions.xml + ZIPs) from GitHub
# over HTTPS, verifies each ZIP's SHA-1, stores it in the LMS cache folder and
# offers it to SqueezePlay's Applet Installer. The players then download the
# ZIPs from LMS itself (http://<lms>:9000/sbradio/applets/<zip>), the same way
# they get firmware from LMS. This avoids the players' lack of HTTPS support.

use strict;
use base qw(Slim::Plugin::Base);

use Digest::SHA1;
use File::Spec::Functions qw(catdir catfile);
use XML::Simple;

use Slim::Control::Jive;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Slim::Utils::Versions;

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.sbradio',
	defaultLevel => 'INFO',
	description  => 'PLUGIN_SBRADIO',
});

my $prefs = preferences('plugin.sbradio');
$prefs->init({
	repoUrl  => 'https://raw.githubusercontent.com/macsatcom/SBRadio/main/extensions.xml',
	interval => 6 * 3600,
});

my $RAW_PATH = 'sbradio/applets';
my $cacheDir;
my @entries;      # verified applet entries currently offered
my $syncing = 0;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	$cacheDir = catdir(preferences('server')->get('cachedir'), 'SBRadio');
	mkdir $cacheDir unless -d $cacheDir;

	# Serve verified ZIPs over plain HTTP on the LMS web port
	Slim::Web::Pages->addRawDownload("^$RAW_PATH/", \&_fileForPath, 'binary');

	# Offer the applets to the Applet Installer (no optstr -> always shown)
	Slim::Control::Jive::registerExtensionProvider('sbradio', \&getExtensions);

	# Use the last good index straight away, so it works without internet
	_loadIndex(_readFile(catfile($cacheDir, 'extensions.xml')), 1);

	Slim::Utils::Timers::setTimer(undef, time() + 15, \&sync);
}

sub shutdownPlugin {
	Slim::Control::Jive::removeExtensionProvider('sbradio');
	Slim::Web::Pages->removeRawDownload("^$RAW_PATH/");
	Slim::Utils::Timers::killTimers(undef, \&sync);
}

sub _fileForPath {
	my $path = shift;
	my ($name) = $path =~ m{^\Q$RAW_PATH\E/([A-Za-z0-9._-]+\.zip)$};
	return '' unless $name;
	return catfile($cacheDir, $name);
}

sub _sha1File {
	my $file = shift;
	open my $fh, '<', $file or return '';
	binmode $fh;
	my $d = Digest::SHA1->new->addfile($fh)->hexdigest;
	close $fh;
	return $d;
}

sub _readFile {
	my $file = shift;
	open my $fh, '<', $file or return;
	binmode $fh;
	local $/;
	my $c = <$fh>;
	close $fh;
	return $c;
}

sub _parse {
	my $content = shift;
	my $xml = eval {
		XMLin($content,
			SuppressEmpty => undef,
			KeyAttr       => { title => 'lang', desc => 'lang', changes => 'lang' },
			ContentKey    => '-content',
			GroupTags     => { applets => 'applet' },
			ForceArray    => [ 'applet', 'title', 'desc', 'changes' ],
		);
	};
	if ($@ || ref $xml ne 'HASH') {
		$log->warn("cannot parse extensions.xml: $@");
		return;
	}
	return ref $xml->{applets} eq 'ARRAY' ? $xml->{applets} : [];
}

sub _zipName {
	my ($name) = ($_[0] || '') =~ m{([A-Za-z0-9._-]+\.zip)$};
	return $name;
}

# Build the offered list from an index; only entries whose ZIP is present
# locally with the right SHA-1 are offered.
sub _loadIndex {
	my ($content, $quiet) = @_;
	return 0 unless $content;
	my $list = _parse($content) or return 0;

	my @ok;
	for my $e (@$list) {
		my $zip = _zipName($e->{url});
		my $sha = lc($e->{sha} || '');
		next unless $zip && $sha && $e->{name} && $e->{version};
		my $file = catfile($cacheDir, $zip);
		if (-r $file && _sha1File($file) eq $sha) {
			push @ok, { %$e, zip => $zip, sha => $sha };
		}
		elsif (!$quiet) {
			$log->warn("$zip not available or checksum wrong; not offered");
		}
	}
	@entries = @ok;
	main::INFOLOG && $log->info(sprintf("offering %d applet entries", scalar @entries));
	return 1;
}

sub sync {
	Slim::Utils::Timers::killTimers(undef, \&sync);
	Slim::Utils::Timers::setTimer(undef, time() + ($prefs->get('interval') || 21600), \&sync);
	return if $syncing;
	$syncing = 1;

	my $url = $prefs->get('repoUrl');
	main::INFOLOG && $log->info("fetching $url");

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
			my $content = $http->content;
			my $list = _parse($content);
			if (!$list) { $syncing = 0; return; }
			_downloadAll($content, $list);
		},
		sub {
			my ($http, $error) = @_;
			$log->warn("cannot fetch $url: $error");
			$syncing = 0;
		},
		{ timeout => 60 },
	)->get($url, 'User-Agent' => Slim::Utils::Misc::userAgentString('legacy'));
}

sub _downloadAll {
	my ($content, $list) = @_;

	my %todo;
	for my $e (@$list) {
		my $zip = _zipName($e->{url}) or next;
		my $sha = lc($e->{sha} || '') or next;
		my $file = catfile($cacheDir, $zip);
		next if -r $file && _sha1File($file) eq $sha;
		$todo{$zip} = { url => $e->{url}, sha => $sha, file => $file };
	}

	my $pending = scalar keys %todo;
	my $finish = sub {
		_loadIndex($content);
		# keep the index for offline restarts
		if (open my $fh, '>', catfile($cacheDir, 'extensions.xml')) {
			binmode $fh; print $fh $content; close $fh;
		}
		_prune();
		$syncing = 0;
	};

	return $finish->() unless $pending;

	for my $zip (keys %todo) {
		my $t = $todo{$zip};
		my $tmp = "$t->{file}.part";
		main::INFOLOG && $log->info("downloading $t->{url}");

		my $done = sub {
			if (-r $tmp && _sha1File($tmp) eq $t->{sha}) {
				rename $tmp, $t->{file};
				main::INFOLOG && $log->info("verified $zip");
			}
			else {
				unlink $tmp;
				$log->error("checksum mismatch or download failed for $zip");
			}
			$finish->() unless --$pending;
		};

		Slim::Networking::SimpleAsyncHTTP->new(
			$done,
			sub { $log->warn("download of $zip failed: $_[1]"); $done->() },
			{ saveAs => $tmp, timeout => 300 },
		)->get($t->{url}, 'User-Agent' => Slim::Utils::Misc::userAgentString('legacy'));
	}
}

# remove ZIPs no longer offered
sub _prune {
	my %keep = map { $_->{zip} => 1 } @entries;
	opendir my $dh, $cacheDir or return;
	for my $f (readdir $dh) {
		next unless $f =~ /\.zip$/ && !$keep{$f};
		unlink catfile($cacheDir, $f);
		main::INFOLOG && $log->info("removed old $f");
	}
	closedir $dh;
}

# Extension provider called for "jiveapplets" queries from the players
sub getExtensions {
	my $args = shift;

	my @res;
	if (($args->{type} || '') eq 'applet') {
		my $target  = $args->{target};
		my $version = $args->{version};
		my $lang    = $args->{lang} || 'EN';
		my $base    = Slim::Utils::Network::serverURL();

		for my $e (@entries) {
			next if $target && $e->{target} && $e->{target} !~ /^(?:$target)$/;
			next if $version && $e->{minTarget} && $e->{maxTarget}
				&& !Slim::Utils::Versions->checkVersion($version, $e->{minTarget}, $e->{maxTarget});

			my $pick = sub {
				my $v = $e->{$_[0]};
				return ref $v eq 'HASH' ? ($v->{$lang} || $v->{EN} || '') : (ref $v ? '' : $v);
			};

			push @res, {
				name    => $e->{name},
				version => $e->{version},
				sha     => $e->{sha},
				title   => $pick->('title') || $e->{name},
				desc    => $pick->('desc'),
				changes => $pick->('changes'),
				creator => ref $e->{creator} ? '' : $e->{creator},
				# relurl: the player builds http://<ip it uses for LMS>:<port><relurl>
				relurl  => "/$RAW_PATH/$e->{zip}",
				url     => "$base/$RAW_PATH/$e->{zip}",
			};
		}
	}

	$args->{cb}->(@{ $args->{pt} }, \@res);
}

1;
