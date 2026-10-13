#!/bin/perl -v 

use Sentry::Raven 

my $sentry =  Sentry::Raven->new( sentry_dsn => 'https://3b3f7609ce084c9f94973abe7f9c0717:e623429a07b54a6a85a417fe1580db41@sentry.io/1416669' );

$sentry->capture_message("Test from perl via Sentry::Raven");

