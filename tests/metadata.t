#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use JSON::PP qw(decode_json);
use lib "$FindBin::Bin/../lib";

# Simulate only the standard metadata-loader contract, not its FHEM internals.
BEGIN {
    package FHEM::Meta;
    sub getMetadata {
        my ($file, $meta) = @_;
        open my $fh, '<:raw', $file or die $!;
        local $/; my $text = <$fh>;
        $text =~ /=for :application\/json;q=META\.json GeoSphereAPI\.pm\s*\n(.*?)\n=end :application\/json;q=META\.json/s
          or die 'missing metadata block';
        %$meta = %{JSON::PP::decode_json($1)};
        return;
    }
    $INC{'FHEM/Meta.pm'} = __FILE__;
}
use FHEM::APIs::Weather::GeoSphereAPI;
our %packages;
my $meta = $packages{GeoSphereAPI}{META};
is(ref($meta), 'HASH', 'FHEM package metadata registered');
is($meta->{version}, 'v'.$FHEM::APIs::Weather::GeoSphereAPI::VERSION, 'metadata/runtime versions match');
is($meta->{release_status}, 'testing', 'beta status explicit');
is($meta->{license}, 'GPL_2', 'standard FHEM license identifier');
is($meta->{prereqs}{runtime}{requires}{'JSON::PP'}, 0, 'core JSON dependency declared');
ok(exists $meta->{prereqs}{runtime}{requires}{'FHEM::Meta'}, 'FHEM metadata dependency declared');
unlike(join(' ', @{$meta->{author}}), qr/prototype/i, 'prototype author removed without fabricated identity');
my $api=FHEM::APIs::Weather::GeoSphereAPI->new({devName=>'meta', location=>'48.2486,16.3564'});
is($api->getWeather->{apiMaintainer}, '50watt (support: FHEM weather forum)', 'maintainer and support destination in API diagnostic');
is_deeply($meta->{x_fhem_maintainer}, ['50watt'], 'confirmed maintainer in FHEM metadata');
is($meta->{resources}{homepage}, 'https://github.com/50watt/fhem-geosphere', 'homepage declared');
is($meta->{resources}{repository}{type}, 'git', 'repository type declared');
is($meta->{resources}{repository}{url}, 'https://github.com/50watt/fhem-geosphere.git', 'clone URL declared');
is($meta->{resources}{repository}{web}, 'https://github.com/50watt/fhem-geosphere', 'repository web URL declared');
is($meta->{resources}{bugtracker}{web}, 'https://github.com/50watt/fhem-geosphere/issues', 'support destination declared');
like($meta->{x_lang}{de}{abstract}, qr/GeoSphere Austria.*FHEM Weather/, 'German description declared');
ok(!grep(/^fhem-mod(?:-|$)/, @{$meta->{keywords}}), 'Weather provider does not claim to be a device module');
for my $dependency (qw(strict warnings utf8 JSON::PP POSIX Time::Local Scalar::Util Encode Unicode::Normalize FHEM::Meta HttpUtils)) {
    ok(exists $meta->{prereqs}{runtime}{requires}{$dependency}, "runtime dependency declared: $dependency");
}
done_testing;
