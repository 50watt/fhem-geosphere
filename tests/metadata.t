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
done_testing;
