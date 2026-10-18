use strict;use warnings;use utf8;use Test::More;use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
use JSON::PP qw(decode_json encode_json);use Encode qw(decode_utf8);
my $class='FHEM::APIs::Weather::GeoSphereAPI';
my $api=$class->new({devName=>'test',location=>'48.2486,16.3564',language=>'de'});
# Source: official NWP-v2 migration help, sy table (page 2).
my @names=qw(clear mostly_clear partly_cloudy mostly_cloudy cloudy ground_fog low_stratus light_rain moderate_rain heavy_rain sleet sleet sleet light_snow moderate_snow heavy_snow rain_shower rain_shower heavy_rain_shower sleet_shower sleet_shower sleet_shower snow_shower snow_shower heavy_snow_shower thunderstorm thunderstorm severe_thunderstorm thunderstorm_with_sleet severe_thunderstorm_with_sleet thunderstorm_with_snow severe_thunderstorm_with_snow);
for my $i (1..32) {
 my ($code,$condition,$name)=$api->_symbol_condition($i);
 is($name,$names[$i-1],"official symbol $i meaning");
 ok(defined $code && $code>=0 && $code<=47,"symbol $i has existing Weather code");
 ok(length($condition)>0,"symbol $i has German description");
}
for my $bad (undef,'',0,33,999,'3.5','NaN',[]) {
 my @mapped=$api->_symbol_condition($bad);is(scalar @mapped,0,'unsupported symbol does not invent mapping');
}
open my $fh,'<',"$FindBin::Bin/fixtures/forecast.json" or die $!;
my $source=decode_json(do {local $/;<$fh>});
sub copy {decode_json(encode_json($_[0]))}
my $now=$class->can('_epoch')->($source->{timestamps}[0])-60;
for my $case ([1,'Klar',32,'clear'],[6,'Bodennebel',20,'ground_fog'],[7,'Hochnebel',26,'low_stratus'],[10,'Starker Regen',35,'heavy_rain'],[25,'Starke Schneeschauer',43,'heavy_snow_shower'],[32,'Starkes Gewitter mit Schnee',3,'severe_thunderstorm_with_snow']) {
 my ($symbol,$de,$code,$name)=@$case;my $data=copy($source);
 my $params=$data->{features}[0]{properties}{parameters};
 $params->{sy}{data}=[($symbol)x@{$data->{timestamps}}];
 # Contradictory cloud/rain values must not overwrite an official symbol.
 $params->{tcc}{data}=[(90)x@{$data->{timestamps}}];
 my $fc=$api->_forecast($data,$now);
 my $hour=$fc->{hourly}[0];my $day=$fc->{daily}[0];
 is($hour->{condition},$de,"hour uses official $name despite cloud cover");
 is($hour->{code},$code,"hour selects FHEM code for $name");
 is($hour->{conditionSource},'official GeoSphere sy','official source explicit');
 is($day->{geoSphereSymbol},$symbol,'daily representative symbol retained');
 like($day->{conditionSource},qr/representative hour/,'daily scope explicit');
 is($day->{condition},$de,'daily description agrees with representative symbol');
 my $wire=$class->can('_wire')->($fc);
 is(decode_utf8($wire->{hourly}[0]{condition}),$de,'UTF-8 boundary preserves text');
}
for my $bad (undef,999) {
 my $data=copy($source);$data->{features}[0]{properties}{parameters}{sy}{data}=[($bad)x@{$data->{timestamps}}];
 my $fc=$api->_forecast($data,$now);
 like($fc->{hourly}[0]{conditionSource},qr/approximate.*missing or unsupported/,'missing or new symbol uses declared fallback');
 is($fc->{daily}[0]{geoSphereSymbol},'','fallback daily aggregation has no official daily symbol');
 like($fc->{daily}[0]{conditionSource},qr/daily mean cloud cover/,'fallback preserves daily aggregation');
}
$api->{lang}='en';my (undef,$english)=$api->_symbol_condition(30);
is($english,'Severe thunderstorm with sleet','English language supported');
done_testing;
