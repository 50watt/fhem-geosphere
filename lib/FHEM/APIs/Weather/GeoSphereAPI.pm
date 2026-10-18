# SPDX-License-Identifier: GPL-2.0-or-later
# $Id$
# GeoSphere Austria provider for FHEM Weather. Version 0.2.8, beta.
# Data: GeoSphere Austria, CC BY 4.0. See README.md for attribution.
package FHEM::APIs::Weather::GeoSphereAPI;

use strict;
use warnings;
use utf8;
use JSON::PP     qw(decode_json);
use POSIX        qw(strftime);
use Time::Local  qw(timegm timelocal);
use Scalar::Util qw(looks_like_number refaddr);

our $VERSION = '0.2.8';

# Use the standard FHEM metadata loader when running inside FHEM. Standalone
# parser/installer checks deliberately need no complete FHEM installation.
my $META = {};
if ( eval { require FHEM::Meta; FHEM::Meta->can('getMetadata') } ) {
    my $error = FHEM::Meta::getMetadata( __FILE__, $META );
    die "GeoSphereAPI metadata: $@ $error" if $@ || $error;
    no warnings 'once';
    $main::packages{GeoSphereAPI}{META} = $META;
}
use Encode             qw(encode_utf8);
use Unicode::Normalize qw(NFKD);
my %METADATA;
my $BASE = 'https://dataset.api.hub.geosphere.at/v1';

sub new {
    my ( $class, $args ) = @_;
    my %options;
    for ( split /,/, $args->{apioptions} // '' ) {
        next if $_ eq '';
        my ( $k, $v ) = split /:/, $_, 2;
        die "GeoSphereAPI: invalid option $_\n"
          unless defined $v
          && $k =~
          /^(station|cachemaxage|forecastcache|timeout|observationmaxage|forecastmaxage|nowcast)$/;
        die "GeoSphereAPI: invalid value for $k\n"
          unless $v =~ /^\d+$/ || ( $k eq 'station' && $v eq 'auto' );
        die "GeoSphereAPI: nowcast must be 0 or 1\n" if $k eq 'nowcast' && $v !~ /^[01]$/;
        $options{$k} = $v eq 'auto' ? $v : 0 + $v;
    }
    my $self = bless {
        devName           => $args->{devName},
        lang              => $args->{language} // 'de',
        nowcastOption     => $options{nowcast} // 0,
        stationOption     => $options{station} // 'auto',
        station           => ( $options{station} // '' ) =~ /^\d+$/ ? $options{station} : undef,
        initialLocation   => $args->{location},
        cachemaxage       => $options{cachemaxage}       // 600,
        forecastcache     => $options{forecastcache}     // 1800,
        timeout           => $options{timeout}           // 20,
        observationmaxage => $options{observationmaxage} // 1800,
        forecastmaxage    => $options{forecastmaxage}    // 32400,
        fetchTime         => 0,
        forecast          => '',
        generation        => 0,
        constructing      => 1,
    }, $class;
    die "GeoSphereAPI: timeout must be 1..120 seconds\n"
      unless $self->{timeout} >= 1 && $self->{timeout} <= 120;
    $self->_sync_location;
    $self->_sync_altitude;
    $self->_station_dropdown( [] );
    $self->{cached} = $self->_base;
    delete $self->{constructing};
    return $self;
}

sub _base {
    my ($self) = @_;
    return {
        lat           => $self->{lat},
        long          => $self->{long},
        country       => 'AT',
        apiMaintainer => '50watt (support: FHEM weather forum)',
        apiVersion    => $VERSION,
        source        => 'GeoSphere Austria',
        sourceURL     => 'https://data.hub.geosphere.at/',
        license       => {
            text =>
'GeoSphere Austria | CC BY 4.0 | https://creativecommons.org/licenses/by/4.0/ | units converted; daily forecasts aggregated'
        },
        status   => 'not fetched',
        validity => 'stale',
    };
}

sub setLocation {
    my ( $self, $lat, $lon, $from_sync ) = @_;
    die "GeoSphereAPI: location must be latitude,longitude\n"
      unless defined $lat
      && defined $lon
      && $lat =~ /^-?\d+(?:\.\d+)?$/
      && $lon =~ /^-?\d+(?:\.\d+)?$/
      && $lat >= -90
      && $lat <= 90
      && $lon >= -180
      && $lon <= 180;
    $self->{runtimeLocation} = "$lat,$lon" unless $from_sync;

    # Discard cached model data and invalidate outstanding callbacks.
    $self->{generation}++;
    delete @{$self}{
        qw(busy model modelFetched pendingCurrent forecastError forecastLastReference referenceEpoch warningsFetched warningsData warningsLocation nowcastData nowcastFetched nowcastFinished nowcastError selectedAuto metadataDone)
    };
    $self->{fetchTime} = 0;
    ( $self->{lat}, $self->{long} ) = ( 0 + $lat, 0 + $lon );
    if ( $self->{cached} ) {
        $self->_invalidate_forecast( 'location changed; pending update', 'pending' );
        $self->{cached}{status}           = 'location changed; pending update';
        $self->{cached}{validity}         = 'stale';
        $self->{cached}{warningsStatus}   = 'pending';
        $self->{cached}{warningsValidity} = 'unknown';
        $self->{cached}{warningsCount}    = $self->{cached}{warnCount} = 'unknown';
        $self->{cached}{warningsArea}     = '';
        $self->{cached}{alerts}           = [];
        for ( keys %{ $self->{cached} } ) { delete $self->{cached}{$_} if /^rain15m_/; }
        $self->{cached}{rainNextHour}    = 'unknown';
        $self->{cached}{rainNextHour_mm} = '';
        $self->{cached}{nowcastPoints}   = 0;
        $self->{cached}{nowcastStatus}   = 'pending';
        $self->{cached}{nowcastValidity} = 'unknown';

        for (
            qw(rainNextHourFrom rainNextHourTo nextRainPeriodStart nextRainPeriodEnd nowcastReferenceTime nowcastFetchedAt nowcastLatitude nowcastLongitude)
          )
        {
            $self->{cached}{$_} = '';
        }
        my $device;
        { no warnings 'once'; $device = $main::defs{ $self->{devName} }; }
        if ( $device && $device->{fhem}{api} && refaddr( $device->{fhem}{api} ) == refaddr($self) )
        {
            main::CommandDeleteReading( undef, "$self->{devName} warn_[0-9]+_.*" )
              if defined &main::CommandDeleteReading;
            $self->_notify;
        }
    }
    return;
}

sub setForecast {
    my ( $self, $selection ) = @_;
    $self->{forecast}  = $selection // '';
    $self->{fetchTime} = 0;
    return;
}

sub _forecast_enabled {
    my ($self) = @_;
    my $selection =
      defined &main::AttrVal
      ? main::AttrVal( $self->{devName}, 'forecast', $self->{forecast} )
      : $self->{forecast};
    return $selection =~ /(?:^|,)(?:hourly|daily)(?:,|$)/ ? 1 : 0;
}

# All FHEM-specific access is kept behind an identity-checked boundary.
sub _device {
    my ($self) = @_;
    no warnings 'once';
    my $device = $main::defs{ $self->{devName} };
    return unless $device;
    return $device if $self->{constructing};
    return
      unless $device->{fhem}{api}
      && refaddr( $device->{fhem}{api} ) == refaddr($self);
    return $device;
}

sub _active {
    my ($self) = @_;
    return defined $self->_device;
}

sub _invalidate_forecast {
    my ( $self, $message, $state ) = @_;
    my $out = $self->{cached};
    $out->{forecastStatus}        = $state // 'stale';
    $out->{forecastValidity}      = $state && $state eq 'disabled' ? 'disabled' : 'stale';
    $out->{forecastLastError}     = $message;
    $out->{forecast}              = { hourly => [], daily => [] };
    $out->{forecastDaysAvailable} = $out->{forecastHoursAvailable} = 0;
    delete @{$self}{qw(model modelFetched)};
    return;
}
sub setAlerts    { $_[0]{alerts}    = $_[1] ? 1 : 0; return; }
sub setFetchTime { $_[0]{fetchTime} = time;          return; }
sub getFetchTime { return $_[0]{fetchTime}; }
sub getWeather   { return $_[0]{cached}; }

sub _notify {
    my ($self) = @_;

    # A deleted or redefined Weather device must not receive an old response.
    my $device;
    { no warnings 'once'; $device = $main::defs{ $self->{devName} }; }
    return
         unless $device
      && $device->{fhem}{api}
      && refaddr( $device->{fhem}{api} ) == refaddr($self);

    # Weather does not remove trailing records when a forecast horizon shrinks.
    # Delete only obsolete forecast indices on this provider's own device.
    if ( defined &main::CommandDeleteReading ) {
        my %obsolete;
        for my $reading ( keys %{ $device->{READINGS} // {} } ) {
            if ( $reading =~ /^rain15m_(\d+)_/ ) {
                $obsolete{ sprintf( 'rain15m_%02d_.*', $1 ) } = 1
                  if $1 > ( $self->{cached}{nowcastPoints} // 0 );
                next;
            }
            next unless $reading =~ /^(h?fc)(\d+)_/;
            my ( $prefix, $index ) = ( $1, $2 );
            my $kind = $prefix eq 'fc' ? 'daily' : 'hourly';
            $obsolete{"${prefix}${index}_.*"} = 1
              if $index > @{ $self->{cached}{forecast}{$kind} // [] };
        }
        main::CommandDeleteReading( undef, "$self->{devName} $_" ) for sort keys %obsolete;
    }
    if ( defined &FHEM::Core::Weather::RetrieveCallbackFn ) {
        FHEM::Core::Weather::RetrieveCallbackFn( $self->{devName} );
    }
    elsif ( defined &main::Weather_RetrieveCallbackFn ) {
        main::Weather_RetrieveCallbackFn( $self->{devName} );
    }
    elsif ( defined &main::Weather_CallbackFn ) {
        main::Weather_CallbackFn( $self->{devName} );
    }
    else {
        die "GeoSphereAPI: unsupported Weather callback interface\n";
    }
    if (   $self->{cached}{status} eq 'ok'
        && $self->_alerts_enabled
        && ( $self->{cached}{warningsStatus} // '' ) ne 'ok'
        && defined &main::readingsSingleUpdate )
    {
        main::readingsSingleUpdate( $device, 'warnCount', 'unknown', 1 );
    }
    return;
}

sub _error {
    my ( $self, $message ) = @_;

    # Weather retains the last successful readings and exposes lastError.
    $message =~ s/[\r\n]+/ /g;
    $self->{cached}{status}   = 'GeoSphere: ' . substr( $message, 0, 240 );
    $self->{cached}{validity} = 'stale';
    if ( !$self->_forecast_enabled ) {
        $self->_invalidate_forecast( '', 'disabled' );
    }
    else {
        my $age = defined $self->{referenceEpoch} ? time - $self->{referenceEpoch} : undef;
        $self->{cached}{forecastAge_s} = defined $age ? $age : '';
        $self->{cached}{forecastAge} =
          defined $age && $age >= 0
          ? int( $age / 3600 ) . ' h ' . sprintf( '%02d', int( $age % 3600 / 60 ) ) . ' min'
          : '';
        if ( !defined $age || $age > $self->{forecastmaxage} || $age < -300 ) {
            $self->_invalidate_forecast(
                'forecast expired or unavailable during observation failure');
        }
    }
    delete $self->{cached}{alerts};
    if ( $self->_alerts_enabled ) {
        $self->{cached}{warningsStatus}   = 'error';
        $self->{cached}{warningsValidity} = 'unknown';
        $self->{cached}{warningsCount}    = $self->{cached}{warnCount} = 'unknown';
        $self->{cached}{warningsLastError} =
          'warning refresh not completed: ' . substr( $message, 0, 160 );
    }
    delete @{$self}{qw(busy pendingCurrent)};
    if ( $self->_nowcast_enabled ) {
        my %rain = (
            rainNextHour     => 'unknown',
            rainNextHour_mm  => '',
            nowcastPoints    => 0,
            nowcastStatus    => 'error',
            nowcastValidity  => 'unknown',
            nowcastLastError => 'refresh not completed: ' . substr( $message, 0, 160 )
        );
        @{ $self->{cached} }{ keys %rain } = values %rain;
        my $device;
        { no warnings 'once'; $device = $main::defs{ $self->{devName} }; }
        if ( $device && $device->{fhem}{api} && refaddr( $device->{fhem}{api} ) == refaddr($self) )
        {
            main::CommandDeleteReading( undef, "$self->{devName} rain15m_[0-9]+_.*" )
              if defined &main::CommandDeleteReading;
            if ( defined &main::readingsSingleUpdate ) {
                main::readingsSingleUpdate( $device, $_, $rain{$_}, 1 ) for keys %rain;
            }
        }
    }
    $self->_notify;
    return;
}

sub setRetrieveData {
    my ($self) = @_;
    my $ok = eval { $self->_sync_location; $self->_sync_altitude; $self->_sync_station; 1 };
    return $self->_error($@) unless $ok;
    return if $self->{busy};
    delete $self->{metadataDone}
      if $self->{metadataChecked} && time - $self->{metadataChecked} > 86400;
    if ( !$self->{metadataDone} ) {
        $self->{busy} = 1;
        return $self->_stations;
    }
    my $now = time;
    my $rain_ready =
      $self->_nowcast_enabled
      ? ( ( $self->{cached}{nowcastStatus} // '' ) eq 'ok'
          && $now - ( $self->{nowcastFetched}  // 0 ) < 900
          && $now - ( $self->{nowcastParsedAt} // 0 ) < 60 )
      : ( ( $self->{cached}{nowcastStatus} // '' ) eq 'disabled' );
    if (
           $rain_ready
        && $self->{cached}{status} eq 'ok'
        && $now - $self->{fetchTime} < $self->{cachemaxage}
        && $now - $self->{observationEpoch} <= $self->{observationmaxage}
        && (
            !$self->_forecast_enabled
            || ( ( $self->{cached}{forecastStatus} // '' ) eq 'ok'
                && $now - ( $self->{referenceEpoch} // 0 ) <= $self->{forecastmaxage} )
        )
        && (
            !$self->_alerts_enabled
            || ( ( $self->{warningsState} // '' ) eq 'ok'
                && $now - ( $self->{warningsFetched} // 0 ) < 300 )
        )
        && (
            ( $self->_alerts_enabled && ( $self->{cached}{warningsStatus} // '' ) ne 'disabled' )
            || ( !$self->_alerts_enabled
                && ( $self->{cached}{warningsStatus} // '' ) eq 'disabled' )
        )
      )
    {
        return $self->_notify;
    }
    return $self->_start_weather;
}

sub _start_weather {
    my ($self) = @_;
    $self->{busy} = 1;
    my $generation = ++$self->{generation};
    delete $self->{forecastError};
    $self->_request( 'current', $generation,
"$BASE/station/current/tawes-v1-10min?parameters=TL,RF,P,PRED,FF,DD,FFX,RR,TP,GLOW,SO&station_ids=$self->{station}"
    );
    return;
}

sub _request_error {
    my ( $self, $kind, $message ) = @_;
    return $self->_error($message) unless $kind eq 'forecast';

    # A forecast outage must not suppress a fresh observation or warning request.
    $message =~ s/[\r\n]+/ /g;
    $self->{forecastError} = substr( $message, 0, 240 );
    return $self->_finish;
}

sub _request {
    my ( $self, $kind, $generation, $url ) = @_;
    my $param = {
        url      => $url,
        timeout  => $self->{timeout},
        method   => 'GET',
        header   => 'Accept: application/json',
        callback => sub {
            my ( $p, $error, $body ) = @_;
            return if $generation != $self->{generation} || !$self->_active;
            return $self->_request_error( $kind, "$kind request: $error" ) if $error;
            return $self->_request_error( $kind, "$kind HTTP " . ( $p->{code} // 'unknown' ) )
              if defined $p->{code} && $p->{code} != 200;
            my $data = eval { decode_json( $body // '' ) };
            return $self->_request_error( $kind, "$kind invalid JSON" )
              if $@ || ref($data) ne 'HASH';
            my $ok = eval {
                if ( $kind eq 'current' ) {
                    $self->{pendingCurrent} = $self->_current( $data, time );
                }
                else {
                    # Keep reference diagnostics even when rejecting a stale model.
                    $self->{forecastLastReference} = $data->{reference_time} // '';

                    # Validate before caching; never cache an invalid response.
                    $self->_forecast( $data, time );
                    $self->{model}        = $data;
                    $self->{modelFetched} = time;
                }
                1;
            };
            return $self->_request_error( $kind, "$kind: $@" ) unless $ok;
            if ( $kind eq 'current' ) {
                return $self->_finish unless $self->_forecast_enabled;
                if ( $self->{model} && time - $self->{modelFetched} < $self->{forecastcache} ) {
                    my $usable = eval { $self->_forecast( $self->{model}, time ); 1 };
                    return $self->_finish if $usable;
                    delete @{$self}{qw(model modelFetched)};
                }
                return $self->_request( 'forecast', $generation,
"$BASE/timeseries/forecast/nwp-v2-1h-1km?parameters=2t,2r,msl,10u,10v,10fg,tp,rain,sf,tcc,sy,ssrd,sund&lat_lon=$self->{lat},$self->{long}"
                );
            }
            return $self->_finish;
        },
    };
    my $ok = eval { main::HttpUtils_NonblockingGet($param); 1 };
    $self->_request_error( $kind, "HTTP client: $@" ) unless $ok;
    return;
}

sub _finish {
    my ($self) = @_;
    my $now    = time;
    my $result = eval {
        my $observation = $self->{pendingCurrent};
        die "observation expired\n" if $now - $observation->{epoch} > $self->{observationmaxage};
        my $fc = $self->{model} ? eval { $self->_forecast( $self->{model}, $now ) } : undef;
        my $forecastError = $@ || $self->{forecastError} || ( $fc ? '' : 'forecast unavailable' );
        my $enabled       = $self->_forecast_enabled;
        if ( !$enabled ) {
            $fc            = undef;
            $forecastError = '';
        }
        $forecastError =~ s/[\r\n]+/ /g;
        my $reference =
          $fc ? $self->{model}{reference_time} : ( $self->{forecastLastReference} // '' );
        my $referenceEpoch = eval { _epoch($reference) };
        my $out            = $self->_base;
        $out->{forecastStatus} =
           !$enabled ? 'disabled'
          : $fc      ? 'ok'
          : ( $forecastError =~ /forecast stale/ ? 'stale' : 'error' );
        $out->{forecastValidity}  = !$enabled ? 'disabled' : $fc ? 'up-to-date' : 'stale';
        $out->{forecastLastError} = substr( $forecastError, 0, 240 );
        $out->{forecastAge_s}     = defined $referenceEpoch ? $now - $referenceEpoch : '';

        # Remove unavailable forecast records instead of leaving old indices usable.
        if ( !$fc ) {
            delete @{$self}{qw(model modelFetched)};
            $fc = { hourly => [], daily => [], lat => '', lon => '', referenceEpoch => 0 };
        }
        $out->{current} = $observation->{readings};

        # Include hourly and daily series; Weather decides which to publish.
        $out->{forecast}               = { hourly => $fc->{hourly}, daily => $fc->{daily} };
        $out->{current_date_time}      = $out->{current}{pubDate};
        $out->{forecastReferenceTime}  = $reference;
        $out->{forecastSource}         = 'GeoSphere nwp-v2-1h-1km';
        $out->{forecastLatitude}       = $fc->{lat};
        $out->{forecastLongitude}      = $fc->{lon};
        $out->{forecastDaysAvailable}  = scalar @{ $fc->{daily} };
        $out->{forecastHoursAvailable} = scalar @{ $fc->{hourly} };
        $out->{observationStation}     = $self->{station};
        my $station = $self->{stationInfo} // {};
        $out->{stationName}      = $station->{name}     // '';
        $out->{stationLatitude}  = $station->{lat}      // '';
        $out->{stationLongitude} = $station->{lon}      // '';
        $out->{stationAltitude}  = $station->{altitude} // '';
        $out->{stationDistanceKm} =
          defined $station->{lat} ? _round( $self->_distance($station) ) : '';
        $out->{stationSelection}       = $self->{stationChoice};
        $out->{locationAltitude}       = $self->{altitude} // '';
        $out->{locationAltitudeSource} = $self->{altitudeSource};
        $out->{stationSelectionMethod} =
            ( $self->{stationChoice} // '' ) ne 'auto' ? 'manual'
          : defined $self->{altitude}                  ? 'distance-altitude'
          :                                              'distance-only; target altitude missing';
        $out->{selectedStationTargetAltitude} = $self->{altitude} // '';
        $out->{stationAltitudeDifference_m} =
          defined $self->{altitude} && defined _number( $station->{altitude} )
          ? _round( $station->{altitude} - $self->{altitude} )
          : '';
        $out->{stationSelectionScore} =
          defined $station->{lat} ? _round( $self->_station_score($station) ) : '';
        $out->{stationAvailableReadings} = join ',',
          grep { defined $observation->{readings}{$_} && $observation->{readings}{$_} ne '' }
          qw(temperature humidity pressure wind wind_direction wind_gust rain10min_mm stationPressure dewPoint globalRadiation sunshineDuration_s);
        $out->{stationMetadataStatus} = $self->{metadataStatus} // 'unknown';
        $out->{locationSource}        = $self->{locationSource};
        $out->{status}                = 'ok';
        $out->{validity}              = 'up-to-date';
        $self->{observationEpoch}     = $observation->{epoch};
        $self->{referenceEpoch}       = $fc->{referenceEpoch};
        $out;
    };
    if ($@) {
        my $error = $@;
        delete @{$self}{qw(model modelFetched)};
        return $self->_error($error);
    }
    if ( $self->_alerts_enabled && !$self->{warningsFinished} ) {
        $self->{weatherResult} = $result;
        return $self->_warnings_request;
    }
    if ( $self->_nowcast_enabled && !$self->{nowcastFinished} ) {
        return $self->_nowcast_request;
    }
    $self->_publish($result);

    return;
}

sub _epoch {
    my ($text) = @_;
    die "invalid ISO timestamp\n"
      unless defined $text
      && $text =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:\d{2})$/;
    my ( $y, $m, $d, $h, $min, $s, $offset ) = ( $1, $2, $3, $4, $5, $6 // 0, $7 );
    die "invalid ISO timestamp range\n" if $h > 23 || $min > 59 || $s > 59;
    my $epoch = timegm( $s, $min, $h, $d, $m - 1, $y );
    die "invalid calendar date\n" unless strftime( '%Y-%m-%d', gmtime($epoch) ) eq "$y-$m-$d";
    if ( $offset ne 'Z' ) {
        $offset =~ /^([+-])(\d{2}):(\d{2})$/;
        die "invalid timezone offset\n" if $2 > 23 || $3 > 59;
        $epoch -= ( $1 eq '+' ? 1 : -1 ) * ( $2 * 3600 + $3 * 60 );
    }
    return $epoch;
}

sub _number {
    my ($v) = @_;
    return undef
      unless defined $v
      && !ref($v)
      && looks_like_number($v)
      && "$v" !~ /nan|inf/i
      && $v > -900;
    return 0 + $v;
}
sub _round { return 0 + sprintf( '%.1f', $_[0] ); }

sub _feature {
    my ($data) = @_;
    die "expected one GeoJSON feature\n"
      unless ref( $data->{features} ) eq 'ARRAY'
      && @{ $data->{features} } == 1
      && ref( $data->{features}[0]{properties}{parameters} ) eq 'HASH';
    die "missing timestamps\n"
      unless ref( $data->{timestamps} ) eq 'ARRAY' && @{ $data->{timestamps} };
    return $data->{features}[0];
}

sub _value {
    my ( $p, $key, $i, $unit ) = @_;
    return undef                     unless ref( $p->{$key} ) eq 'HASH';
    die "unexpected unit for $key\n" unless ( $p->{$key}{unit} // '' ) eq $unit;
    return undef                     unless ref( $p->{$key}{data} ) eq 'ARRAY';
    return _number( $p->{$key}{data}[$i] );
}

sub _current {
    my ( $self, $data, $now ) = @_;
    my $f = _feature($data);
    die "wrong station\n" unless ( $f->{properties}{station} // '' ) eq "$self->{station}";
    my $epoch = _epoch( $data->{timestamps}[0] );
    die "observation stale or in future\n"
      if $now - $epoch > $self->{observationmaxage} || $epoch - $now > 300;
    my $p        = $f->{properties}{parameters};
    my $t        = _value( $p, 'TL',   0, '°C' );
    my $rh       = _value( $p, 'RF',   0, '%' );
    my $wind     = _value( $p, 'FF',   0, 'm/s' );
    my $pressure = _value( $p, 'PRED', 0, 'hPa' );
    die "missing essential observation (TL/RF/FF/PRED)\n"
      unless defined $t && defined $rh && defined $wind && defined $pressure;
    die "observation outside physical range\n"
      unless $t >= -80
      && $t <= 65
      && $rh >= 0
      && $rh <= 100
      && $wind >= 0
      && $wind <= 150
      && $pressure >= 800
      && $pressure <= 1100;
    my %r = (
        temperature     => $t,
        temp_c          => $t,
        humidity        => $rh,
        pressure        => $pressure,
        wind            => _round( $wind * 3.6 ),
        wind_speed      => _round( $wind * 3.6 ),
        pressureSource  => 'PRED (sea level)',
        measurementTime => $data->{timestamps}[0],
        pubDate         => strftime( '%a, %e %b %Y %H:%M', localtime($epoch) ),
        code            => 48,
        condition       => (
            $self->{lang} eq 'de'
            ? 'Wetterzustand nicht beobachtet'
            : 'Weather condition not observed'
        ),
        conditionSource => 'not observed; no model substituted',
        wind_direction  => '',
        wind_condition  => '',
        wind_gust       => '',
        rain10min_mm    => '',
        stationPressure => '',

        # An empty value is deliberate: temperature is not apparent temperature.
        apparentTemperature => '',
        tempFeelsLike_c     => '',
    );
    my $dd = _value( $p, 'DD', 0, '°' );
    $r{wind_direction} = $dd if defined $dd && $dd >= 0 && $dd <= 360;
    my $gust = _value( $p, 'FFX', 0, 'm/s' );
    $r{wind_gust} = _round( $gust * 3.6 ) if defined $gust && $gust >= 0;
    my $rr = _value( $p, 'RR', 0, 'mm' );
    $r{rain10min_mm} = $rr if defined $rr && $rr >= 0;
    my $stationp = _value( $p, 'P', 0, 'hPa' );
    $r{stationPressure} = $stationp if defined $stationp && $stationp > 0;
    my $dew = _value( $p, 'TP', 0, '°C' );
    $r{dewPoint}       = defined $dew && $dew >= -100 && $dew <= $t + 1 ? $dew : '';
    $r{dewPointSource} = $r{dewPoint} ne '' ? 'GeoSphere station TP'           : 'unavailable';
    my $radiation = _value( $p, 'GLOW', 0, 'W/m²' );
    $r{globalRadiation} =
      defined $radiation && $radiation >= 0 && $radiation <= 2000 ? $radiation : '';
    $r{globalRadiationUnit}   = 'W/m²';
    $r{globalRadiationSource} = 'GeoSphere station GLOW';
    my $sunshine = _value( $p, 'SO', 0, 'sec' );
    $r{sunshineDuration_s} =
      defined $sunshine && $sunshine >= 0 && $sunshine <= 600 ? $sunshine : '';
    $r{sunshineDurationSource} = 'GeoSphere station SO; preceding 10 minutes';
    $r{sunshinePeriodStart}    = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $epoch - 600 ) );
    $r{sunshinePeriodEnd}      = $data->{timestamps}[0];
    return { epoch => $epoch, readings => \%r };
}

# Bolton/Magnus inversion over liquid water; this is a derived approximation,
# not a GeoSphere observed or explicitly supplied forecast dew point.
sub _dew_point {
    my ( $temperature, $humidity ) = @_;
    return '' unless defined $humidity && $humidity > 0 && $humidity <= 100;
    my $alpha = log( $humidity / 100 ) + 17.67 * $temperature / ( 243.5 + $temperature );
    return _round( 243.5 * $alpha / ( 17.67 - $alpha ) );
}

# Accumulations end at their timestamp. Midnight belongs to the preceding
# accumulation day, unlike instantaneous temperature/cloud samples.
sub _daily_amounts {
    my ( $self, $date, $rows ) = @_;
    my ( $year, $month, $day ) = split /-/, $date;
    my $start     = timelocal( 0, 0, 0, $day, $month - 1, $year );
    my @next      = localtime( $start + 36 * 3600 );
    my $end       = timelocal( 0, 0, 0, $next[3], $next[4], $next[5] + 1900 );
    my @intervals = grep { $_->{epoch} - 3600 >= $start && $_->{epoch} <= $end } @$rows;
    my $expected  = ( $end - $start ) / 3600;
    my $complete =
         @intervals == $expected
      && $intervals[0]{epoch} == $start + 3600
      && $intervals[-1]{epoch} == $end;
    my %result = (
        precipitationExpectedSamples => $expected,
        precipitationPeriodStart     => @intervals
        ? strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $intervals[0]{epoch} - 3600 ) )
        : '',
        precipitationPeriodEnd => @intervals ? $intervals[-1]{timestamp} : '',
        precipitationSource    => 'sum of GeoSphere hourly tp over available local-day intervals',
        rainTotalSource        => 'sum of GeoSphere hourly rain over available local-day intervals',
        sunshineDurationSource => 'sum of GeoSphere hourly sund over available local-day intervals',
    );

    for my $spec (
        [ 'precipitation', 'precipitation', 'precipitationCoverage', 'precipitationSamples',   3 ],
        [ 'rain1h',        'rainTotal_mm',  'rainCoverage',          'rainSamples',            3 ],
        [ 'snowWaterEquivalent', 'snowWaterEquivalent', 'snowCoverage',     'snowSamples',     3 ],
        [ 'sunshineDuration_s',  'sunshineDuration_s',  'sunshineCoverage', 'sunshineSamples', 1 ],
      )
    {
        my ( $source, $target, $coverage, $samples, $precision ) = @$spec;
        my @values =
          map { $_->{$source} } grep { defined $_->{$source} && $_->{$source} ne '' } @intervals;
        $result{$samples} = scalar @values;
        my $usable = @intervals && @values == @intervals;
        my $sum    = 0;
        $sum += $_ for @values;
        $result{$target} = $usable ? 0 + sprintf( "%.${precision}f", $sum ) : '';
        $result{$coverage} =
          !@intervals ? 'missing' : !$usable ? 'unknown' : $complete ? 'complete' : 'partial';
    }
    @result{qw(sunshinePeriodStart sunshinePeriodEnd)} =
      @result{qw(precipitationPeriodStart precipitationPeriodEnd)};
    for my $spec ( [ 'precipitation', 'precipitationHours' ],
        [ 'snowWaterEquivalent', 'snowfallHours' ] )
    {
        my ( $source, $target ) = @$spec;
        my @values =
          map { $_->{$source} } grep { defined $_->{$source} && $_->{$source} ne '' } @intervals;
        $result{$target} =
          @intervals && @values == @intervals ? scalar( grep { $_ >= 0.1 } @values ) : '';
    }
    return \%result;
}

# GeoSphere sy table: official NWP-v2 migration help, page 2.
# Weather codes select the closest existing FHEM icon; sy remains authoritative.
my %SYMBOLS = (
    1  => [ 32, 'Klar',                             'clear' ],
    2  => [ 34, 'Überwiegend klar',                 'mostly_clear' ],
    3  => [ 30, 'Leicht bewölkt',                   'partly_cloudy' ],
    4  => [ 28, 'Stark bewölkt',                    'mostly_cloudy' ],
    5  => [ 26, 'Bedeckt',                          'cloudy' ],
    6  => [ 20, 'Bodennebel',                       'ground_fog' ],
    7  => [ 26, 'Hochnebel',                        'low_stratus' ],
    8  => [ 12, 'Leichter Regen',                   'light_rain' ],
    9  => [ 12, 'Mäßiger Regen',                    'moderate_rain' ],
    10 => [ 35, 'Starker Regen',                    'heavy_rain' ],
    11 => [ 5,  'Schneeregen',                      'sleet' ],
    12 => [ 5,  'Schneeregen',                      'sleet' ],
    13 => [ 5,  'Schneeregen',                      'sleet' ],
    14 => [ 14, 'Leichter Schneefall',              'light_snow' ],
    15 => [ 16, 'Mäßiger Schneefall',               'moderate_snow' ],
    16 => [ 15, 'Starker Schneefall',               'heavy_snow' ],
    17 => [ 40, 'Regenschauer',                     'rain_shower' ],
    18 => [ 40, 'Regenschauer',                     'rain_shower' ],
    19 => [ 45, 'Starke Regenschauer',              'heavy_rain_shower' ],
    20 => [ 5,  'Schneeregenschauer',               'sleet_shower' ],
    21 => [ 5,  'Schneeregenschauer',               'sleet_shower' ],
    22 => [ 5,  'Schneeregenschauer',               'sleet_shower' ],
    23 => [ 46, 'Schneeschauer',                    'snow_shower' ],
    24 => [ 46, 'Schneeschauer',                    'snow_shower' ],
    25 => [ 43, 'Starke Schneeschauer',             'heavy_snow_shower' ],
    26 => [ 4,  'Gewitter',                         'thunderstorm' ],
    27 => [ 4,  'Gewitter',                         'thunderstorm' ],
    28 => [ 3,  'Starkes Gewitter',                 'severe_thunderstorm' ],
    29 => [ 4,  'Gewitter mit Schneeregen',         'thunderstorm_with_sleet' ],
    30 => [ 3,  'Starkes Gewitter mit Schneeregen', 'severe_thunderstorm_with_sleet' ],
    31 => [ 4,  'Gewitter mit Schnee',              'thunderstorm_with_snow' ],
    32 => [ 3,  'Starkes Gewitter mit Schnee',      'severe_thunderstorm_with_snow' ],
);

sub _symbol_condition {
    my ( $self, $symbol ) = @_;
    return
      unless defined $symbol && !ref($symbol) && "$symbol" =~ /^\d+$/ && exists $SYMBOLS{$symbol};
    my ( $code, $de, $name ) = @{ $SYMBOLS{$symbol} };
    my $en = $name;
    $en =~ s/_/ /g;
    $en = ucfirst $en;
    return ( $code, $self->{lang} eq 'de' ? $de : $en, $name );
}

sub _condition {
    my ( $self, $cloud, $rain, $snow ) = @_;

    # This is an explicit local approximation, NOT the GeoSphere symbol table.
    my ( $code, $de, $en ) = ( 48, 'Unbekannt', 'Unknown' );
    if    ( defined $snow && $snow >= 0.1 ) { ( $code, $de, $en ) = ( 16, 'Schneefall', 'Snow' ); }
    elsif ( defined $rain && $rain >= 0.1 ) { ( $code, $de, $en ) = ( 12, 'Regen',      'Rain' ); }
    elsif ( defined $cloud ) {
        ( $code, $de, $en ) =
            $cloud < 20 ? ( 32, 'Überwiegend klar', 'Mostly clear' )
          : $cloud < 50 ? ( 30, 'Leicht bewölkt',   'Partly cloudy' )
          : $cloud < 80 ? ( 28, 'Stark bewölkt',    'Mostly cloudy' )
          :               ( 26, 'Bedeckt', 'Overcast' );
    }
    return ( $code, $self->{lang} eq 'de' ? $de : $en );
}

sub _forecast {
    my ( $self, $data, $now ) = @_;
    my $f   = _feature($data);
    my $ref = _epoch( $data->{reference_time} );
    die "forecast stale: reference age " . ( $now - $ref ) . "s exceeds $self->{forecastmaxage}s\n"
      if $now - $ref > $self->{forecastmaxage};
    die "forecast reference in future\n" if $ref - $now > 300;
    my $p = $f->{properties}{parameters};
    my ( @hourly, @all, %days, $previous );
    my $today = strftime( '%Y-%m-%d', localtime($now) );

    for my $i ( 0 .. $#{ $data->{timestamps} } ) {
        my $epoch = _epoch( $data->{timestamps}[$i] );
        die "forecast timestamps not hourly\n" if defined $previous && $epoch != $previous + 3600;
        $previous = $epoch;
        my $date = strftime( '%Y-%m-%d', localtime($epoch) );
        next if $date lt $today;
        my $t = _value( $p, '2t', $i, 'degree Celsius' );
        die "missing forecast temperature\n" unless defined $t && $t >= -80 && $t <= 65;
        my $rh        = _value( $p, '2r',   $i, '%' );
        my $msl       = _value( $p, 'msl',  $i, 'Pa' );
        my $u         = _value( $p, '10u',  $i, 'm s-1' );
        my $v         = _value( $p, '10v',  $i, 'm s-1' );
        my $gust      = _value( $p, '10fg', $i, 'm s-1' );
        my $rain      = _value( $p, 'tp',   $i, 'kg m-2' );
        my $liquid    = _value( $p, 'rain', $i, 'kg m-2' );
        my $snow      = _value( $p, 'sf',   $i, 'kg m-2' );
        my $cloud     = _value( $p, 'tcc',  $i, '%' );
        my $symbol    = _value( $p, 'sy',   $i, '1' );
        my $radiation = _value( $p, 'ssrd', $i, 'W m-2' );
        my $sunshine  = _value( $p, 'sund', $i, 's' );
        $cloud = undef if defined $cloud && ( $cloud < 0 || $cloud > 100 );
        $rain  = undef if defined $rain  && $rain < 0;
        $snow  = undef if defined $snow  && $snow < 0;
        my ( $code, $condition, $symbolName ) = $self->_symbol_condition($symbol);
        my $conditionSource = 'official GeoSphere sy';

        if ( !defined $code ) {
            ( $code, $condition ) = $self->_condition( $cloud, $rain, $snow );
            $conditionSource =
              'derived from tp, sf, tcc; approximate; GeoSphere sy missing or unsupported';
        }
        my %row = (
            epoch               => $epoch,
            date                => $date,
            timestamp           => $data->{timestamps}[$i],
            pubDate             => strftime( '%a, %e %b %Y %H:%M', localtime($epoch) ),
            day_of_week         => strftime( '%a, %H:%M',          localtime($epoch) ),
            temperature         => $t,
            temp_c              => $t,
            code                => $code,
            condition           => $condition,
            conditionSource     => $conditionSource,
            geoSphereSymbolName => $symbolName // '',
            dewPoint            => _dew_point( $t, $rh ),
            dewPointSource      => 'calculated from GeoSphere 2t/2r; Bolton/Magnus over water',
            globalRadiation     => defined $radiation
              && $radiation >= 0
              && $radiation <= 2000 ? $radiation : '',
            globalRadiationUnit   => 'W/m²',
            globalRadiationSource => 'GeoSphere ssrd',
            sunshineDuration_s    => defined $sunshine
              && $sunshine >= 0
              && $sunshine <= 3600 ? $sunshine : '',
            sunshineDurationSource => 'GeoSphere sund; preceding forecast hour',
            sunshinePeriodStart    => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $epoch - 3600 ) ),
            sunshinePeriodEnd      => $data->{timestamps}[$i],
            humidity               => defined $rh     && $rh >= 0 && $rh <= 100 ? $rh : '',
            pressure               => defined $msl    && $msl > 0 ? _round( $msl / 100 ) : '',
            cloudCover             => defined $cloud  && $cloud >= 0 && $cloud <= 100 ? $cloud : '',
            precipitation          => defined $rain   && $rain >= 0   ? $rain   : '',
            rain1h                 => defined $liquid && $liquid >= 0 ? $liquid : '',
            rain1hSource             => 'GeoSphere rain; liquid precipitation forecast interval',
            precipitationUnit        => 'mm',
            precipitationSource      => 'GeoSphere tp; total precipitation water equivalent',
            precipitationPeriodStart => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $epoch - 3600 ) ),
            precipitationPeriodEnd   => $data->{timestamps}[$i],
            snowWaterEquivalent      => defined $snow && $snow >= 0 ? $snow   : '',
            geoSphereSymbol          => defined $symbol             ? $symbol : '',
            wind                     => '',
            wind_speed               => '',
            wind_direction           => '',
            wind_condition           => '',
            wind_gust                => '',
        );
        if ( defined $u && defined $v ) {
            $row{wind} = $row{wind_speed} = _round( sqrt( $u * $u + $v * $v ) * 3.6 );
            if ( $row{wind} > 0 ) {
                my $direction = atan2( -$u, -$v ) * 180 / atan2( 0, -1 ) + 360;
                $direction -= 360 if $direction >= 360;
                $row{wind_direction} = _round($direction);
            }
        }
        $row{wind_gust} = _round( $gust * 3.6 ) if defined $gust && $gust >= 0;
        push @{ $days{$date} }, \%row;
        push @all,              \%row;
        push @hourly,           \%row if $epoch > $now;
    }
    die "forecast does not cover next hour\n"
      unless @hourly >= 4 && $hourly[0]{epoch} <= $now + 3600;
    my @daily;

    # Weather/HomeMode use calendar slots: fc1 today, fc2 tomorrow. An explicit
    # unknown slot is safer than relabelling tomorrow's weather as today's.
    if ( !exists $days{$today} ) {
        push @daily,
          {
            ( map { $_ => '' } keys %{ $hourly[0] } ),
            periodStart         => '',
            periodEnd           => '',
            representativeTime  => '',
            minMaxScope         => '',
            date                => $today,
            epoch               => $now,
            day_of_week         => strftime( '%a', localtime($now) ),
            code                => 48,
            condition           => $self->{lang} eq 'de' ? 'Unbekannt' : 'Unknown',
            coverage            => 'missing',
            samples             => 0,
            low_c               => '',
            high_c              => '',
            tempLow             => '',
            tempHigh            => '',
            temperature         => '',
            temp_c              => '',
            precipitation       => '',
            rain1h              => '',
            snowWaterEquivalent => '',
            conditionSource     => 'no hourly samples for this calendar day',
            summaryCondition    => '',
            summarySource       => '',
            %{ $self->_daily_amounts( $today, \@all ) },
          };
    }
    for my $date ( sort keys %days ) {
        my @rows           = @{ $days{$date} };
        my @temp           = sort { $a <=> $b } map { $_->{temperature} } @rows;
        my $representative = $rows[ int( @rows / 2 ) ];
        my @clouds         = map { $_->{cloudCover} } grep { $_->{cloudCover} ne '' } @rows;
        my $sumCloud       = 0;
        $sumCloud += $_ for @clouds;
        my $meanCloud = @clouds ? _round( $sumCloud / @clouds ) : undef;
        my $amounts   = $self->_daily_amounts( $date, \@all );
        my $wet       = grep { ( $_->{precipitation}       || 0 ) >= 0.1 } @rows;
        my $snowy     = grep { ( $_->{snowWaterEquivalent} || 0 ) >= 0.1 } @rows;
        my ( $dayCode, $dayCondition ) =
          $self->_condition( $meanCloud, $wet ? 1 : 0, $snowy ? 1 : 0 );
        $dayCondition = ( $self->{lang} eq 'de' ? 'Zeitweise ' : 'Occasional ' ) . $dayCondition
          if $wet || $snowy;

        # Daily symbols describe the same representative hour as other daily fields.
        # Without an official symbol, retain the documented daily aggregation.
        my $official = ( $representative->{conditionSource} // '' ) eq 'official GeoSphere sy';
        if ($official) { ( $dayCode, $dayCondition ) = @{$representative}{qw(code condition)}; }
        my $first = $rows[0]{epoch};
        my $last  = $rows[-1]{epoch};

        # Local midnight boundaries handle 23/25-hour DST days correctly.
        my $complete =
             strftime( '%H:%M', localtime($first) ) eq '00:00'
          && strftime( '%H:%M', localtime($last) ) eq '23:00'
          && @rows == int( ( $last - $first ) / 3600 ) + 1;
        push @daily, {
            %$representative,
            date                => $date,
            day_of_week         => strftime( '%a', localtime($first) ),
            low_c               => $temp[0],
            high_c              => $temp[-1],
            tempLow             => $temp[0],
            tempHigh            => $temp[-1],
            code                => $dayCode,
            condition           => $dayCondition,
            cloudCover          => defined $meanCloud ? $meanCloud                             : '',
            geoSphereSymbol     => $official          ? $representative->{geoSphereSymbol}     : '',
            geoSphereSymbolName => $official          ? $representative->{geoSphereSymbolName} : '',
            conditionSource     => $official
            ? 'official GeoSphere sy; representative hour'
            : 'daily mean cloud cover; precipitation occurrence; GeoSphere sy missing or unsupported',
            representativeTime => $representative->{timestamp},
            coverage           => $complete ? 'complete' : 'partial',
            samples            => scalar @rows,
            periodStart        => $rows[0]{timestamp},
            periodEnd          => $rows[-1]{timestamp},
            minMaxScope        => 'available hourly temperature samples',

            # Preserve official representative-hour icons while exposing a separate
            # explicitly derived summary and occurrence counts for the day window.
            summaryCondition => (
                $self->{lang} eq 'de'
                ? sprintf(
                    'Verfügbarer Zeitraum: %s, Niederschlagsstunden: %s, Schneefallstunden: %s',
                    ( $self->_condition( $meanCloud, 0, 0 ) )[1],
                    $amounts->{precipitationHours} ne ''
                    ? $amounts->{precipitationHours}
                    : 'unbekannt',
                    $amounts->{snowfallHours} ne '' ? $amounts->{snowfallHours} : 'unbekannt'
                  )
                : sprintf(
                    'Available period: %s, precipitation hours: %s, snowfall hours: %s',
                    ( $self->_condition( $meanCloud, 0, 0 ) )[1],
                    $amounts->{precipitationHours} ne ''
                    ? $amounts->{precipitationHours}
                    : 'unknown',
                    $amounts->{snowfallHours} ne '' ? $amounts->{snowfallHours} : 'unknown'
                )
            ),
            summarySource =>
'derived from available instantaneous cloud samples and hourly interval amounts; approximate',

            # Single-hour liquid rain must not masquerade as a daily total.
            rain1h       => '',
            rain1hSource => 'use rainTotal_mm with rainCoverage for daily rain',
            %$amounts,
        };
    }
    my $coordinates = $f->{geometry}{coordinates};
    die "missing model coordinates\n" unless ref($coordinates) eq 'ARRAY' && @$coordinates >= 2;
    return {
        hourly         => \@hourly,
        daily          => \@daily,
        referenceEpoch => $ref,
        lat            => $coordinates->[1],
        lon            => $coordinates->[0]
    };
}

# Runtime location: explicit DEF coordinates override current global attributes.
sub _sync_location {
    my ($self) = @_;
    my $definition = '';
    {
        no warnings 'once';
        $definition = $main::defs{ $self->{devName} }{DEF} // '' if defined $self->{devName};
    }
    my ( $location, $source );
    if ( $definition =~ /(?:^|\s)location=(\S+)/ ) {
        ( $location, $source ) = ( $1, 'device' );
    }
    elsif ( defined &main::AttrVal ) {
        my $lat = main::AttrVal( 'global', 'latitude',  '' );
        my $lon = main::AttrVal( 'global', 'longitude', '' );
        ( $location, $source ) = ( "$lat,$lon", 'global' ) if $lat ne '' && $lon ne '';
    }
    ( $location, $source ) = ( $self->{initialLocation}, 'Weather resolved location' )
      unless defined $location;
    my $configured = $source . ':' . ( $location // '' );
    delete $self->{runtimeLocation}
      if defined $self->{configuredLocation}
      && $configured ne $self->{configuredLocation};
    $self->{configuredLocation} = $configured;
    if ( defined $self->{runtimeLocation} ) {
        ( $location, $source ) = ( $self->{runtimeLocation}, 'newLocation' );
    }
    my ( $lat, $lon ) = split /,/, $location // '';
    $self->setLocation( $lat, $lon, 1 )
      if !defined $self->{lat}
      || !defined $lat
      || !defined $lon
      || $lat ne $self->{lat}
      || $lon ne $self->{long};
    $self->{locationSource} = $source;
}

# A remote device must never inherit the home's altitude by accident.
sub _sync_altitude {
    my ($self) = @_;
    my ( $altitude, $source ) = ( undef, 'missing' );
    if ( defined &main::AttrVal ) {
        my $own = main::AttrVal( $self->{devName}, 'geoSphereAltitude', '' );
        if ( $own ne '' ) {
            die "invalid geoSphereAltitude; expected metres above sea level (-500..9000)\n"
              unless defined _number($own) && $own >= -500 && $own <= 9000;
            ( $altitude, $source ) = ( 0 + $own, 'device' );
        }
        else {
            my $lat = _number( main::AttrVal( 'global', 'latitude',  '' ) );
            my $lon = _number( main::AttrVal( 'global', 'longitude', '' ) );
            if (   defined $lat
                && defined $lon
                && abs( $lat - $self->{lat} ) < 0.000001
                && abs( $lon - $self->{long} ) < 0.000001 )
            {
                my $value = main::AttrVal( 'global', 'altitude', '' );
                if ( $value ne '' ) {
                    die "invalid global altitude (-500..9000)\n"
                      unless defined _number($value) && $value >= -500 && $value <= 9000;
                    ( $altitude, $source ) = ( 0 + $value, 'global' );
                }
            }
        }
    }
    my $key = $source . ':' . ( $altitude // '' );
    if ( defined $self->{altitudeKey} && $key ne $self->{altitudeKey} ) {
        $self->{generation}++;
        delete @{$self}{
            qw(busy model modelFetched pendingCurrent forecastError forecastLastReference selectedAuto metadataDone)
        };
        delete $self->{station} if ( $self->{stationChoice} // $self->{stationOption} ) eq 'auto';
        $self->{fetchTime} = 0;
    }
    ( $self->{altitude}, $self->{altitudeSource}, $self->{altitudeKey} ) =
      ( $altitude, $source, $key );
    return;
}

sub _station_score {
    my ( $self, $station ) = @_;
    my $distance = $self->_distance($station);
    return $distance unless defined $self->{altitude};
    my $height = _number( $station->{altitude} );

    # Transparent heuristic: 100 metres mismatch adds five distance points.
    # Stations without height metadata rank behind nearby known-height stations.
    return $distance + ( defined $height ? abs( $height - $self->{altitude} ) / 20 : 50 );
}

sub _rank_stations {
    my ( $self, $stations ) = @_;
    return [
        sort {
                 $self->_station_score($a) <=> $self->_station_score($b)
              || $self->_distance($a) <=> $self->_distance($b)
              || $a->{id} cmp $b->{id}
        } @$stations
    ];
}

sub _sync_station {
    my ($self) = @_;
    my $choice =
      defined &main::AttrVal ? main::AttrVal( $self->{devName}, 'geoSphereStation', '' ) : '';
    $choice = $self->{stationOption} if $choice eq '';
    my $station;
    if    ( $choice =~ /^\d+$/ )     { $station = $choice; }
    elsif ( $choice =~ /__(\d+)__/ ) { $station = $1; }
    elsif ( $choice ne 'auto' )      { die "invalid geoSphereStation selection\n"; }
    my $changed = defined $self->{stationChoice} && $choice ne $self->{stationChoice};

    if ($changed) {
        $self->{generation}++;
        delete @{$self}{
            qw(busy model modelFetched pendingCurrent forecastError forecastLastReference selectedAuto metadataDone)
        };
        $self->{fetchTime} = 0;
    }
    $self->{stationChoice} = $choice;
    $self->{station}       = $station if defined $station;
    if ( $choice eq 'auto' ) {
        my $saved =
          defined &main::ReadingsVal
          ? main::ReadingsVal( $self->{devName}, 'selectedStation', '' )
          : '';
        my $savedLocation =
          defined &main::ReadingsVal
          ? main::ReadingsVal( $self->{devName}, 'selectedStationLocation', '' )
          : '';
        my $savedChoice =
          defined &main::ReadingsVal
          ? main::ReadingsVal( $self->{devName}, 'stationSelection', '' )
          : '';
        my $savedAltitude =
          defined &main::ReadingsVal
          ? main::ReadingsVal( $self->{devName}, 'selectedStationTargetAltitude', 'missing' )
          : 'missing';
        my $savedMethod =
          defined &main::ReadingsVal
          ? main::ReadingsVal( $self->{devName}, 'stationSelectionMethod', '' )
          : '';
        my $method =
          defined $self->{altitude}
          ? 'distance-altitude'
          : 'distance-only; target altitude missing';
        $self->{selectedAuto} //= $saved
          if !$changed
          && $savedChoice eq 'auto'
          && $saved =~ /^\d+$/
          && $savedLocation eq "$self->{lat},$self->{long}"
          && $savedMethod eq $method
          && $savedAltitude eq ( $self->{altitude} // '' );
        $self->{station} = $self->{selectedAuto};
    }
    return;
}

sub _json_request {
    my ( $self, $url, $success, $failure ) = @_;
    my $generation = $self->{generation};
    my $ok         = eval {
        main::HttpUtils_NonblockingGet(
            {
                url      => $url,
                timeout  => $self->{timeout},
                method   => 'GET',
                header   => 'Accept: application/json',
                callback => sub {
                    my ( $p, $error, $body ) = @_;
                    return if $self->{generation} != $generation || !$self->_active;
                    return $failure->($error) if $error;
                    return $failure->( 'HTTP ' . ( $p->{code} // 'unknown' ) )
                      if defined $p->{code} && $p->{code} != 200;
                    my $data = eval { decode_json( $body // '' ) };
                    return $failure->('invalid JSON') if $@ || ref($data) ne 'HASH';
                    my $ok = eval { $success->($data); 1 };
                    return $failure->($@) unless $ok;
                    return;
                }
            }
        );
        1;
    };
    $failure->( 'HTTP client: ' . $@ ) unless $ok;
    return;
}

sub _distance {
    my ( $self, $s ) = @_;
    my $r = atan2( 0, -1 ) / 180;
    my $a =
      sin( ( $s->{lat} - $self->{lat} ) * $r / 2 )**2 +
      cos( $self->{lat} * $r ) *
      cos( $s->{lat} * $r ) *
      sin( ( $s->{lon} - $self->{long} ) * $r / 2 )**2;
    $a = 1 if $a > 1;
    return 12742 * atan2( sqrt($a), sqrt( 1 - $a ) );
}

sub _station_list {
    my ( $self, $data ) = @_;
    die "invalid station metadata\n" unless ref( $data->{stations} ) eq 'ARRAY';
    my @stations = grep {
             ref($_) eq 'HASH'
          && $_->{is_active}
          && ( $_->{id} // '' ) =~ /^\d+$/
          && defined _number( $_->{lat} )
          && defined _number( $_->{lon} )
          && $_->{lat} >= -90
          && $_->{lat} <= 90
          && $_->{lon} >= -180
          && $_->{lon} <= 180
          && defined $_->{name}
    } @{ $data->{stations} };
    die "empty active station list\n" unless @stations;
    return [ sort { $self->_distance($a) <=> $self->_distance($b) || $a->{id} cmp $b->{id} }
          @stations ];
}

sub _station_dropdown {
    my ( $self, $stations ) = @_;
    return unless $self->_device;
    my @choices = ('auto');
    for my $s (@$stations) {
        my $name = $s->{name};
        $name =~ s/ä/ae/g;
        $name =~ s/ö/oe/g;
        $name =~ s/ü/ue/g;
        $name =~ s/Ä/Ae/g;
        $name =~ s/Ö/Oe/g;
        $name =~ s/Ü/Ue/g;
        $name =~ s/ß/ss/g;
        $name = NFKD($name);
        $name =~ s/\pM//g;
        $name =~ s/[^A-Za-z0-9_-]+/_/g;
        push @choices,
          $name . '__' . $s->{id} . '__' . sprintf( '%.1f', $self->_distance($s) ) . 'km';
    }
    return $self->_fhem_register_attributes( \@choices );
}

# Weather has no provider attribute-registration or obsolete-reading hook.
# Keep this compatibility adapter separate from parsing and model selection.
sub _fhem_register_attributes {
    my ( $self, $choices ) = @_;
    my $hash = $self->_device or return;

    # Keep generated choices in the runtime attribute list, not in userattr.
    if ( defined &main::setDevAttrList ) {
        no warnings 'once';
        my $dev  = $self->{devName};
        my $list = $hash->{'.AttrList'} // $main::modules{ $hash->{TYPE} // 'Weather' }{AttrList}
          // '';
        $list = join ' ', grep { !/^geoSphere(?:Station|Altitude|Nowcast)(?::|$)/ } split /\s+/,
          $list;
        main::setDevAttrList( $dev,
                $list
              . ' geoSphereAltitude geoSphereStation:'
              . join( ',', @$choices )
              . ' geoSphereNowcast:0,1' );
        if ( exists $main::attr{$dev}{userattr} ) {
            my $remaining = join ' ', grep {
                     !/^geoSphereStation(?::|$)/
                  && !
                  /^[A-Za-z0-9_-]+__\d+__\d+(?:\.\d+)?km(?:,[A-Za-z0-9_-]+__\d+__\d+(?:\.\d+)?km)*$/
              }
              split /\s+/, $main::attr{$dev}{userattr};
            if ( $remaining ne $main::attr{$dev}{userattr} ) {
                if ( length $remaining && defined &main::CommandAttr ) {
                    main::CommandAttr( undef, "$dev userattr $remaining" );
                }
                elsif ( !length $remaining && defined &main::CommandDeleteAttr ) {
                    main::CommandDeleteAttr( undef, "$dev userattr" );
                }
            }
        }
    }
    return;
}

sub _stations {
    my ($self) = @_;
    my $use = sub {
        my ($data) = @_;
        my $stations = $self->_station_list($data);
        $self->_station_dropdown($stations);
        $self->{metadataStatus}  = 'ok';
        $self->{metadataChecked} = time;
        if ( defined $self->{station} ) {
            ( $self->{stationInfo} ) = grep { $_->{id} eq "$self->{station}" } @$stations;
            die "selected station is not active\n" unless $self->{stationInfo};
            $self->{metadataDone} = 1;
            return $self->_start_weather;
        }

        # Rank geography and altitude first, then validate fresh observations.
        my $ranked     = $self->_rank_stations($stations);
        my @candidates = @$ranked[ 0 .. ( @$ranked < 8 ? $#$ranked : 7 ) ];
        my $ids        = join ',', map { $_->{id} } @candidates;
        $self->_json_request(
"$BASE/station/current/tawes-v1-10min?parameters=TL,RF,P,PRED,FF,DD,FFX,RR,TP,GLOW,SO&station_ids=$ids",
            sub {
                my ($observations) = @_;
                die "invalid station probe\n" unless ref( $observations->{features} ) eq 'ARRAY';
                for my $s (@candidates) {
                    my ($feature) = grep { ( $_->{properties}{station} // '' ) eq $s->{id} }
                      @{ $observations->{features} };
                    next unless $feature;
                    $self->{station} = $s->{id};
                    my $obs =
                      eval { $self->_current( { %$observations, features => [$feature] }, time ) };
                    next unless $obs && !$@;
                    $self->{selectedAuto} = $s->{id};
                    $self->{stationInfo}  = $s;
                    $self->{metadataDone} = 1;
                    return $self->_start_weather;
                }
                delete $self->{station};
                die "no suitable fresh station among eight ranked candidates; choose manually\n";
            },
            sub { $self->_error( 'station selection: ' . $_[0] ) }
        );
    };
    if ( $METADATA{data} && time - $METADATA{time} < 86400 ) {
        my $ok = eval { $use->( $METADATA{data} ); 1 };
        return $self->_error($@) unless $ok;
        return;
    }
    return $self->_json_request(
        "$BASE/station/current/tawes-v1-10min/metadata",
        sub {
            my ($data) = @_;
            $self->_station_list($data);
            %METADATA = ( data => $data, time => time );
            $use->($data);
        },
        sub {
            # A manual station remains usable when only the metadata endpoint fails.
            $self->{metadataStatus}  = 'error: ' . $_[0];
            $self->{metadataChecked} = time - 86400 + 300;
            if ( defined $self->{station} ) {
                $self->{metadataDone} = 1;
                return $self->_start_weather;
            }
            $self->_error( 'station metadata: ' . $_[0] );
        }
    );
}

sub _alerts_enabled {
    my ($self) = @_;
    return main::AttrVal( $self->{devName}, 'alerts', $self->{alerts} // 0 ) ? 1 : 0
      if defined &main::AttrVal;
    return $self->{alerts} // 0;
}

sub _warnings_parse {
    my ( $self, $data, $now ) = @_;
    die "invalid warnings response\n"
      unless ( $data->{type} // '' ) eq 'Feature'
      && ref( $data->{properties}{warnings} ) eq 'ARRAY'
      && ref( $data->{properties}{location}{properties} ) eq 'HASH'
      && defined $data->{properties}{location}{properties}{name};
    my @alerts;
    my @types  = ( '', 'Wind',   'Regen',  'Schnee', 'Glatteis', 'Gewitter', 'Hitze', 'Kaelte' );
    my @levels = ( '', 'yellow', 'orange', 'red' );
    for my $warning ( @{ $data->{properties}{warnings} } ) {
        my $w = $warning->{properties};
        die "invalid warning item\n" unless ref($w) eq 'HASH';
        my $raw = $w->{rawinfo} // $w->{rawfinfo} // {};
        my ( $start, $end );
        if ( defined $w->{begin} && $w->{begin} =~ /^\d{4}-/ ) {
            $start = _epoch( $w->{begin} );
            $end   = _epoch( $w->{end} );
        }
        elsif ( ( $raw->{start} // '' ) =~ /^\d{9,12}$/ && ( $raw->{end} // '' ) =~ /^\d{9,12}$/ ) {
            ( $start, $end ) = ( 0 + $raw->{start}, 0 + $raw->{end} );
        }
        else { die "warning has no unambiguous validity interval\n"; }
        die "invalid warning validity interval\n" unless $end > $start;
        next if $end <= $now;
        my $level = $w->{warnstufeid};
        my $type  = $w->{warntypid};
        die "invalid warning severity/type\n"
          unless defined $level
          && "$level" =~ /^[1-3]$/
          && defined $type
          && "$type" =~ /^[1-7]$/;
        die "missing warning id or text\n"
          unless ( $w->{warnid} // '' ) =~ /^\d+$/ && defined $w->{text};
        push @alerts,
          {
            id             => '' . $w->{warnid},
            revision       => $w->{chgid}     // '',
            manifestation  => $w->{verlaufid} // '',
            Start          => strftime( '%Y-%m-%d %H:%M:%S', localtime($start) ),
            End            => strftime( '%Y-%m-%d %H:%M:%S', localtime($end) ),
            startEpoch     => $start,
            endEpoch       => $end,
            phase          => $start > $now ? 'upcoming' : 'active',
            Event          => $types[$type],
            typeId         => $type,
            severity       => $level,
            level          => $levels[$level],
            Headline       => $w->{text},
            Description    => $w->{meteotext}    // '',
            Impact         => $w->{auswirkungen} // '',
            Recommendation => $w->{empfehlungen} // '',
            SenderName     => 'GeoSphere Austria',
            url            => 'https://warnungen.zamg.at/',
          };
    }
    @alerts = sort {
             $b->{severity}   <=> $a->{severity}
          || $a->{startEpoch} <=> $b->{startEpoch}
          || $a->{id} cmp $b->{id}
    } @alerts;
    return { alerts => \@alerts, area => $data->{properties}{location}{properties}{name} };
}

sub _warnings_request {
    my ($self) = @_;
    if (   ( $self->{warningsState} // '' ) eq 'ok'
        && time - ( $self->{warningsFetched} // 0 ) < 300
        && ( $self->{warningsLocation} // '' ) eq "$self->{lat},$self->{long}" )
    {
        $self->{warningsFinished} = 1;
        return $self->_finish;
    }
    my $language = $self->{lang} eq 'de' ? 'de' : 'en';
    $self->_json_request(
"https://warnungen.zamg.at/wsapp/api/getWarningsForCoords?lat=$self->{lat}&lon=$self->{long}&lang=$language",
        sub {
            my ($data) = @_;
            my $parsed = $self->_warnings_parse( $data, time );
            $self->{warningsData}     = $parsed;
            $self->{warningsFetched}  = time;
            $self->{warningsLocation} = "$self->{lat},$self->{long}";
            $self->{warningsState}    = 'ok';
            $self->{warningsError}    = '';
            $self->{warningsFinished} = 1;
            $self->_finish;
        },
        sub {
            $self->{warningsState}    = 'error';
            $self->{warningsError}    = $_[0];
            $self->{warningsFinished} = 1;
            $self->_finish;
        }
    );
    return;
}

sub _nowcast_enabled {
    my ($self) = @_;
    my $value =
      defined &main::AttrVal
      ? main::AttrVal( $self->{devName}, 'geoSphereNowcast', $self->{nowcastOption} )
      : $self->{nowcastOption};
    return defined $value && $value eq '1';
}

sub _nowcast_parse {
    my ( $self, $data, $now ) = @_;
    my $feature   = _feature($data);
    my $reference = _epoch( $data->{reference_time} );
    die "nowcast stale: reference older than 2700s\n" if $now - $reference > 2700;
    die "nowcast reference in future\n"               if $reference - $now > 300;
    my $timestamps = $data->{timestamps};
    die "unexpected nowcast horizon\n" unless @$timestamps >= 4 && @$timestamps <= 24;
    my ( $previous, @rows );

    for my $i ( 0 .. $#$timestamps ) {
        my $end = _epoch( $timestamps->[$i] );
        die "nowcast timestamps not 15 minutes apart\n"
          if defined $previous && $end - $previous != 900;
        $previous = $end;
        next if $end <= $now;
        my $rain = _value( $feature->{properties}{parameters}, 'rr', $i, 'kg m-2' );
        die "missing or invalid nowcast precipitation\n" unless defined $rain && $rain >= 0;
        push @rows, { start => $end - 900, end => $end, mm => $rain };
    }
    die "nowcast does not cover next four quarter-hour periods\n"
      unless @rows >= 4 && $rows[0]{start} <= $now && $rows[0]{end} <= $now + 900;
    my $coordinates = $feature->{geometry}{coordinates};
    die "missing nowcast coordinates\n"
      unless ref($coordinates) eq 'ARRAY'
      && @$coordinates >= 2
      && defined _number( $coordinates->[0] )
      && defined _number( $coordinates->[1] );
    return {
        rows      => \@rows,
        reference => $reference,
        lat       => $coordinates->[1],
        lon       => $coordinates->[0]
    };
}

sub _nowcast_request {
    my ($self) = @_;
    if ( $self->{nowcastData} && time - ( $self->{nowcastFetched} // 0 ) < 900 ) {
        my $ok = eval { $self->_nowcast_parse( $self->{nowcastData}, time ); 1 };
        if ($ok) {
            $self->{nowcastError}    = '';
            $self->{nowcastFinished} = 1;
            return $self->_finish;
        }
    }
    $self->_json_request(
"$BASE/timeseries/forecast/nowcast-v1-15min-1km?parameters=rr&lat_lon=$self->{lat},$self->{long}",
        sub {
            my ($data) = @_;
            $self->_nowcast_parse( $data, time );
            $self->{nowcastData}     = $data;
            $self->{nowcastFetched}  = time;
            $self->{nowcastError}    = '';
            $self->{nowcastFinished} = 1;
            $self->_finish;
        },
        sub {
            my $error = $_[0];
            $error =~ s/[\r\n]+/ /g;
            $self->{nowcastError}    = substr( $error, 0, 240 );
            $self->{nowcastFinished} = 1;
            $self->_finish;
        }
    );
    return;
}

sub _nowcast_readings {
    my ( $self, $now ) = @_;
    my $r = {
        nowcastStatus         => 'disabled',
        nowcastValidity       => 'disabled',
        nowcastLastError      => '',
        nowcastPoints         => 0,
        nowcastReferenceTime  => '',
        nowcastFetchedAt      => '',
        nowcastAge_s          => '',
        nowcastLatitude       => '',
        nowcastLongitude      => '',
        nowcastQueryLatitude  => $self->{lat},
        nowcastQueryLongitude => $self->{long},
        rainNextHour          => 'unknown',
        rainNextHour_mm       => '',
        rainNextHourFrom      => '',
        rainNextHourTo        => '',
        nextRainPeriodStart   => '',
        nextRainPeriodEnd     => ''
    };
    return $r unless $self->_nowcast_enabled;
    $r->{nowcastFetchedAt} = _display_time( $self->{nowcastFetched} );
    my $parsed;
    my $error = $self->{nowcastError} // '';
    if ( !$error ) {
        $parsed = eval { $self->_nowcast_parse( $self->{nowcastData}, $now ) };
        $error  = $@ unless $parsed;
    }
    if ($error) {
        $error =~ s/[\r\n]+/ /g;
        $r->{nowcastStatus}    = $error =~ /stale/ ? 'stale' : 'error';
        $r->{nowcastValidity}  = $error =~ /stale/ ? 'stale' : 'unknown';
        $r->{nowcastLastError} = substr( $error, 0, 240 );
        return $r;
    }
    $self->{nowcastParsedAt}   = $now;
    $r->{nowcastStatus}        = 'ok';
    $r->{nowcastValidity}      = 'up-to-date';
    $r->{nowcastReferenceTime} = _display_time( $parsed->{reference} );
    $r->{nowcastAge_s}         = $now - $parsed->{reference};
    $r->{nowcastLatitude}      = $parsed->{lat};
    $r->{nowcastLongitude}     = $parsed->{lon};
    my @rows = @{ $parsed->{rows} };
    $r->{nowcastPoints} = scalar @rows;
    my $sum = 0;
    $sum += $_->{mm} for @rows[ 0 .. 3 ];

    # The first period may already be underway: expose the actual window.
    $r->{rainNextHour_mm}  = 0 + sprintf( '%.3f', $sum );
    $r->{rainNextHour}     = $sum > 0 ? 'yes' : 'no';
    $r->{rainNextHourFrom} = _display_time( $rows[0]{start} );
    $r->{rainNextHourTo}   = _display_time( $rows[3]{end} );
    for my $i ( 0 .. $#rows ) {
        my $prefix = sprintf( 'rain15m_%02d_', $i + 1 );
        $r->{ $prefix . 'periodStart' } = _display_time( $rows[$i]{start} );
        $r->{ $prefix . 'time' }        = _display_time( $rows[$i]{end} );
        $r->{ $prefix . 'mm' }          = $rows[$i]{mm};
        if ( $rows[$i]{mm} > 0 && $r->{nextRainPeriodStart} eq '' ) {
            $r->{nextRainPeriodStart} = _display_time( $rows[$i]{start} );
            $r->{nextRainPeriodEnd}   = _display_time( $rows[$i]{end} );
        }
    }
    return $r;
}

# Presentation only: raw API timestamps and epochs remain unchanged internally.
sub _display_time {
    my ($epoch) = @_;
    return '' unless defined $epoch;
    return strftime( '%d.%m.%Y %H:%M:%S %Z', localtime($epoch) );
}

sub _display_iso {
    my ($value) = @_;
    return '' unless defined $value && $value ne '';
    my $epoch = eval { _epoch($value) };
    return defined $epoch ? _display_time($epoch) : '';
}

sub _localize_result {
    my ( $self, $result ) = @_;
    my $current = $result->{current};
    if ( ref($current) eq 'HASH' ) {
        my $time = _display_iso( $current->{measurementTime} );
        $current->{measurementTime}  = $current->{pubDate} = $time;
        $result->{current_date_time} = $time;
        for my $key (qw(sunshinePeriodStart sunshinePeriodEnd)) {
            $current->{$key} = _display_iso( $current->{$key} ) if exists $current->{$key};
        }
    }
    $result->{forecastReferenceTime} = _display_iso( $result->{forecastReferenceTime} );
    $result->{warningsFetchedAt}     = _display_iso( $result->{warningsFetchedAt} );
    my $age = $result->{forecastAge_s};
    $result->{forecastAge} =
      defined $age && $age ne '' && $age >= 0
      ? int( $age / 3600 ) . ' h ' . sprintf( '%02d', int( $age % 3600 / 60 ) ) . ' min'
      : '';
    for my $kind (qw(hourly daily)) {
        for my $row ( @{ $result->{forecast}{$kind} // [] } ) {
            $row->{timestamp}   = $row->{pubDate} = _display_time( $row->{epoch} );
            $row->{day_of_week} = $row->{timestamp} if $kind eq 'hourly';
            for my $key (
                qw(periodStart periodEnd representativeTime precipitationPeriodStart precipitationPeriodEnd sunshinePeriodStart sunshinePeriodEnd)
              )
            {
                $row->{$key} = _display_iso( $row->{$key} ) if exists $row->{$key};
            }
        }
    }
    for my $warning ( @{ $result->{alerts} // [] } ) {
        $warning->{Start} = _display_time( $warning->{startEpoch} );
        $warning->{End}   = _display_time( $warning->{endEpoch} );
    }
    return;
}

sub _wire {
    my ($value) = @_;
    return { map { $_ => _wire( $value->{$_} ) } keys %$value } if ref($value) eq 'HASH';
    return [ map { _wire($_) } @$value ]                        if ref($value) eq 'ARRAY';
    return defined $value && utf8::is_utf8($value) ? encode_utf8($value) : $value;
}

sub _publish {
    my ( $self, $result ) = @_;
    my $now = time;
    $result->{selectedStation}         = $self->{station};
    $result->{selectedStationLocation} = "$self->{lat},$self->{long}";
    $result->{warningsLatitude}        = $self->{lat};
    $result->{warningsLongitude}       = $self->{long};
    $result->{warningsLastError}       = '';
    if ( $self->_alerts_enabled ) {
        my $valid = ( $self->{warningsState} // '' ) eq 'ok'
          && $now - ( $self->{warningsFetched} // 0 ) <= 900;
        my $data   = $self->{warningsData};
        my @alerts = $data ? grep { $_->{endEpoch} > $now } @{ $data->{alerts} } : ();
        for (@alerts) { $_->{phase} = $_->{startEpoch} > $now ? 'upcoming' : 'active'; }
        my $max = 0;
        for (@alerts) { $max = $_->{severity} if $_->{severity} > $max; }
        $result->{alerts}           = \@alerts;
        $result->{warningsStatus}   = $valid ? 'ok'           : 'error';
        $result->{warningsValidity} = $valid ? 'up-to-date'   : 'unknown';
        $result->{warningsCount}    = $valid ? scalar @alerts : 'unknown';
        $result->{warningsMaxLevel} = $valid ? $max           : 'unknown';
        $result->{warningsArea}     = $data  ? $data->{area}  : '';
        $result->{warningsFetchedAt} =
          $self->{warningsFetched}
          ? strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $self->{warningsFetched} ) )
          : '';
        $result->{warningsLastError} =
          $valid ? '' : ( $self->{warningsError} // 'warnings unavailable' );
    }
    else {
        $result->{alerts}            = [];
        $result->{warningsStatus}    = 'disabled';
        $result->{warningsValidity}  = 'disabled';
        $result->{warningsCount}     = 'unknown';
        $result->{warningsMaxLevel}  = 'unknown';
        $result->{warningsArea}      = '';
        $result->{warningsFetchedAt} = '';
    }
    my $rain = $self->_nowcast_readings($now);
    @{$result}{ keys %$rain } = values %$rain;
    $self->_localize_result($result);
    $self->{cached}    = _wire($result);
    $self->{fetchTime} = $now;
    delete @{$self}{qw(busy pendingCurrent warningsFinished nowcastFinished weatherResult)};
    $self->_notify;
}

# Compatibility with Weather installations using the pre-namespace API layout.
package GeoSphereAPI::Weather;
our @ISA = ('FHEM::APIs::Weather::GeoSphereAPI');
1;

=pod

=encoding utf8

=for :application/json;q=META.json GeoSphereAPI.pm
{
  "abstract": "GeoSphere Austria observations, forecasts, nowcast and warnings for FHEM Weather",
  "keywords": ["fhem-mod-device", "Weather", "API", "GeoSphere"],
  "version": "v0.2.8",
  "release_status": "testing",
  "license": "GPL_2",
  "author": ["GeoSphereAPI contributors"],
  "x_fhem_maintainer": ["50watt"],
  "prereqs": {
    "runtime": {
      "requires": {
        "perl": "5.016", "FHEM::Meta": 0, "HttpUtils": 0,
        "JSON::PP": 0, "POSIX": 0, "Time::Local": 0,
        "Scalar::Util": 0, "Encode": 0, "Unicode::Normalize": 0
      }
    }
  }
}
=end :application/json;q=META.json

=head1 NAME

GeoSphereAPI - experimental GeoSphere Austria provider for FHEM Weather

=head1 SYNOPSIS

  define WeatherAT Weather API=GeoSphereAPI interval=300 lang=de
  attr WeatherAT geoSphereAltitude 200
  attr WeatherAT geoSphereStation auto
  attr WeatherAT forecast hourly,daily
  attr WeatherAT alerts 1
  attr WeatherAT geoSphereNowcast 1

Commands above are separate FHEMWEB command-line steps. The altitude is an
example and must be replaced by the actual ground elevation above sea level.

=head1 PRECIPITATION NOWCAST

Optional geoSphereNowcast=1 (or API option nowcast:1) requests INCA 15-minute
precipitation for this device location. rain15m_NN_mm is an interval amount in mm;
periodStart and time expose its local boundaries. rainNextHour sums the next
four intervals, including the currently running quarter hour. Its From/To
readings expose the actual window; this is not a sliding 60-minute forecast.
Check nowcastStatus=ok before using rainNextHour. Errors/missing data produce
unknown, never a dry confirmation. Reference age is limited to 2700 seconds;
raw responses are cached at most 900 seconds. This optional request runs after
warnings and cannot turn a rain-only failure into a weather/warning failure.

=head1 LOCATION AND STATIONS

Explicit device location takes precedence over global latitude/longitude.
geoSphereAltitude takes precedence over global altitude. Global altitude is
used only at matching global coordinates, never at an unrelated remote site.
Automatic station ranking adds abs(height difference)/20 to distance in km;
fresh mandatory observations are validated among eight ranked candidates.
Missing target altitude falls back to distance-only ranking and is exposed in
readings. Manual station selection overrides automatic ranking.

=head1 DEW POINT AND SOLAR PARAMETERS

Observed dewPoint is station TP in degrees Celsius. globalRadiation is GLOW
in W/m2 and sunshineDuration_s is SO in seconds over the preceding ten minutes.
Hourly forecasts use ssrd and sund, with local sunshinePeriodStart/End.
Forecast dewPoint is an explicitly labelled Bolton/Magnus approximation from
temperature and relative humidity, not an official GeoSphere dew-point field.
Missing optional values stay empty. Radiation is not PV power or daily energy.

Daily precipitation, rainTotal_mm, snowWaterEquivalent and sunshineDuration_s
sum complete available hourly intervals contained in the local calendar day.
The interval ending at next midnight is included; the one ending at the start
of this day belongs to yesterday. Each amount has separate Coverage and Samples
readings. complete denotes a whole 23/24/25-hour civil day, partial an available
subset, unknown missing values, and missing no eligible intervals. Forecast
amounts never mix observed station totals into the model series.

summaryCondition is a separate derived cloud/precipitation summary. Occurrence
counts use a threshold of 0.1 mm per hour. Official daily condition/icon still
describe the representative hour. No Weather core modification is required.

=head1 WARNINGS AND LIMITATIONS

Warnings are optional and use the weather device coordinates, not its station.
Only a successful empty warnings response confirms zero warnings. Errors leave
counts unknown. Forecast conditions use official sy symbols where available;
missing/unsupported symbols use an explicitly approximate fallback. Current condition and
apparent temperature are not observed. Daily extrema cover available hourly
samples only. DOKUMENTATION.md documents configuration and validity rules;
README.md describes installation and updates.

=head1 LICENSE AND SUPPORT

Code: GPL-2.0-or-later. Data: GeoSphere Austria, CC BY 4.0. Attribution must be
visible when publishing data. Maintainer: 50watt (FHEM weather forum).
No official FHEM inclusion is implied. See README.md and DOKUMENTATION.md.

=cut
