use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;

is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( 0, 5, 'de' ),
    'Wind: N 5 km/h',
    'zero degrees is valid north wind'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( 360, 5, 'de' ),
    'Wind: N 5 km/h',
    '360 degrees wraps to north'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( 67.5, 8, 'de' ),
    'Wind: ONO 8 km/h',
    'German compass direction is localized'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( 180, 0, 'de' ),
    'Wind: S 0 km/h',
    'calm wind retains numeric zero'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( '', 5, 'de' ),
    'Wind: - 5 km/h',
    'missing direction has safe placeholder'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( 270, '', 'de' ),
    'Wind: W - km/h',
    'missing speed has safe placeholder'
);
is(
    FHEM::APIs::Weather::GeoSphereAPI::_wind_condition( '', '', 'en' ),
    'Wind: - - km/h',
    'fully missing wind still produces complete value'
);

done_testing;
