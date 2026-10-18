use strict;use warnings;use Test::More;use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
use POSIX qw(tzset);use JSON::PP qw(encode_json decode_json);
$ENV{TZ}='Europe/Vienna';tzset();
my $c='FHEM::APIs::Weather::GeoSphereAPI';
sub epoch {$c->can('_epoch')->($_[0])}
sub display {$c->can('_display_time')->(epoch($_[0]))}
is(display('2026-01-15T12:00:00Z'),'15.01.2026 13:00:00 CET','winter time');
is(display('2026-07-15T12:00:00Z'),'15.07.2026 14:00:00 CEST','summer time');
is(display('2026-10-25T00:30:00Z'),'25.10.2026 02:30:00 CEST','first repeated autumn hour');
is(display('2026-10-25T01:30:00Z'),'25.10.2026 02:30:00 CET','second repeated autumn hour distinguished');
is(display('2026-03-29T00:30:00Z'),'29.03.2026 01:30:00 CET','before spring gap');
is(display('2026-03-29T01:30:00Z'),'29.03.2026 03:30:00 CEST','after spring gap');
is(display('2026-10-17T23:30:00+02:00'),'17.10.2026 23:30:00 CEST','ISO offset converted correctly');
is($c->can('_display_iso')->(''),'','empty optional time stays empty');
is($c->can('_display_iso')->('invalid'),'','invalid diagnostic reference not invented');
my $raw='2026-10-17T15:00+00:00';my $e=epoch($raw);
my $result={current=>{measurementTime=>$raw,pubDate=>'old'},current_date_time=>'old',
 forecastReferenceTime=>$raw,warningsFetchedAt=>$raw,forecastAge_s=>28023,
 forecast=>{hourly=>[{epoch=>$e,timestamp=>$raw,pubDate=>'old',day_of_week=>'old'}],
 daily=>[{epoch=>$e,timestamp=>$raw,pubDate=>'old',date=>'2026-10-17',day_of_week=>'Sat',periodStart=>$raw,periodEnd=>$raw,representativeTime=>$raw}]},
 alerts=>[{startEpoch=>$e,endEpoch=>$e+3600,Start=>'old',End=>'old'}]};
my $original=encode_json($result);my $api=bless {},$c;$api->_localize_result($result);
my $expected='17.10.2026 17:00:00 CEST';
for my $key (qw(measurementTime pubDate)) {is($result->{current}{$key},$expected,"local current $key")}
for my $key (qw(current_date_time forecastReferenceTime warningsFetchedAt)) {is($result->{$key},$expected,"local $key")}
for my $kind (qw(hourly daily)) {
 for my $key (qw(timestamp pubDate)) {is($result->{forecast}{$kind}[0]{$key},$expected,"local $kind $key")}
 is($result->{forecast}{$kind}[0]{epoch},$e,"$kind epoch unchanged");
}
for my $key (qw(periodStart periodEnd representativeTime)) {is($result->{forecast}{daily}[0]{$key},$expected,"local daily $key")}
is($result->{forecast}{daily}[0]{date},'2026-10-17','calendar date contract preserved');
is($result->{forecast}{daily}[0]{day_of_week},'Sat','daily weekday contract preserved');
is($result->{alerts}[0]{Start},$expected,'warning start local');
is($result->{alerts}[0]{End},'17.10.2026 18:00:00 CEST','warning end local');
is($result->{alerts}[0]{startEpoch},$e,'warning epoch unchanged');
is($result->{forecastAge},'7 h 47 min','human-readable model age');
is($raw,'2026-10-17T15:00+00:00','raw source timestamp unchanged');
my $empty={forecast=>{hourly=>[],daily=>[]},alerts=>[],forecastAge_s=>'',forecastReferenceTime=>'',warningsFetchedAt=>''};
$api->_localize_result($empty);
is($empty->{forecastAge},'','unknown model age not replaced by zero');
is(@{$empty->{forecast}{hourly}},0,'missing forecasts stay absent');
my $created=$c->new({devName=>'test',location=>'48.2486,16.3564'});
is($created->{forecastmaxage},32400,'default model age now nine hours');
$created=$c->new({devName=>'test',location=>'48.2486,16.3564',apioptions=>'forecastmaxage:21600'});
is($created->{forecastmaxage},21600,'explicit old age limit remains configurable');
done_testing;
