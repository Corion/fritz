#!perl
use Test::More tests => 13;
use warnings;
use strict;

use Test::Mock::LWP::Dispatch;
use Digest::MD5 qw(md5_hex);
use Fritz::Box;

BEGIN { use_ok('Fritz::Service') };


### public tests

subtest 'check fritz getter, set via new()' => sub {
    # given
    my $fritz = Fritz::Box->new();
    my $service = new_ok( 'Fritz::Service', [ fritz => $fritz, xmltree => undef ] );

    # when
    my $result = $service->fritz;

    # then
    is( $result, $fritz, 'get fritz' );
};

subtest 'check xmltree getter, set via new()' => sub {
    # given
    my $xmltree = [ some => 'thing' ];
    my $service = new_ok( 'Fritz::Service', [ fritz => undef, xmltree => $xmltree ] );

    # when
    my $result = $service->xmltree;

    # then
    is( $result, $xmltree, 'get xmltree' );
};

subtest 'check for scpd error after HTTP error' => sub {
    # given
    my $xmltree = { SCPDURL => [ '' ] };
    my $fritz = new_ok( 'Fritz::Box' );
    my $service = new_ok( 'Fritz::Service', [ fritz => $fritz, xmltree => $xmltree ] );

    # when
    my $result = $service->scpd;

    # then
    isa_ok( $result, 'Fritz::Error', 'SCPD conversion result' );
};

subtest 'check scpd after successful HTTP GET' => sub {
    # given
    my $service = create_service_with_scpd_data();

    # when
    my $result = $service->scpd;

    # then
    isa_ok( $result, 'Fritz::Data', 'SCPD conversion result' );
    isa_ok( $result->data, 'HASH', 'SCPD result data' );
};

subtest 'check action hash' => sub {
    # given
    my $service = create_service_with_scpd_data();
    my $service_name = 'SomeService';

    # when
    my $result = $service->action_hash;

    # then
    isa_ok( $result, 'HASH', 'action_hash result' );
    ok( exists $result->{$service_name}, 'action exists' );
    isa_ok( $result->{$service_name}, 'Fritz::Action', 'action' );
};

subtest 'check attribute getters' => sub {
    # given
    my $xmltree = {
	'serviceType' => [ 'SRV_TYPE' ],
	'serviceId' => [ 'SRV_ID' ],
	'controlURL' => [ 'CTRL_URL' ],
	'eventSubURL' => [ 'EV_SUB_URL' ],
	'SCPDURL' => [ 'SCPD_URL' ],
    };
    my $service = new_ok( 'Fritz::Service', [ fritz => undef, xmltree => $xmltree ] );

    foreach my $key (keys %{$xmltree}) {
	# when
	my $result = $service->$key;

	# then
	is( $result, $xmltree->{$key}->[0], "$key content" );
    }
};

subtest 'check simple service call' => sub {
    # given
    my $service = create_service_with_scpd_data();
    my $service_name = 'SomeService';
    my @arguments = ('InputArgument' => 'foo');
    $mock_ua->unmap_all;
    $mock_ua->map($service->fritz->upnp_url.$service->controlURL, get_soap_response());

    # when
    my $result = $service->call($service_name, @arguments);

    # then
    # TODO check if parameters were included in the SOAP call
    isa_ok( $result, 'Fritz::Data', 'service response' );
    isa_ok( $result->data, 'HASH', 'service response data' );
    is( $result->data->{OutputArgument}, 'bar', 'OutputArgument' );
};

subtest 'check service call with authentication but no credentials' => sub {
    # given
    my $service = create_service_with_scpd_data();
    my $service_name = 'SomeService';
    my @arguments = ('InputArgument' => 'foo');
    $mock_ua->unmap_all;
    $mock_ua->map($service->fritz->upnp_url.$service->controlURL, get_unauthorized_response());

    # when
    my $result = $service->call($service_name, @arguments);

    # then
    isa_ok( $result, 'Fritz::Error', 'service response' );
    like( $result->error, qr/no credentials/, 'error message' );
};

subtest 'check service call with authentication and credentials' => sub {
    # given
    my $user = 'user';
    my $pass = 'pass';
    my $service = create_service_with_scpd_data( username => $user, password => $pass );
    my $service_name = 'SomeService';
    my @arguments = ('InputArgument' => 'foo');
    $mock_ua->unmap_all;
    $mock_ua->map($service->fritz->upnp_url.$service->controlURL, sub { return authentication(@_) } );

    # when
    my $result = $service->call($service_name, @arguments);

    # then
    isa_ok( $result, 'Fritz::Data', 'service response' );
    isa_ok( $result->data, 'HASH', 'service response data' );
    is( $result->data->{OutputArgument}, 'bar', 'OutputArgument' );
};

subtest 'check for error messages on missing parameters during call()' => sub {
    plan skip_all => 'TODO test not implemented yet';
    ok( 0, 'TODO test missing' );
};


### internal tests

subtest 'check new()' => sub {
    # given

    # when
    my $service = new_ok( 'Fritz::Service' );

    # then
    isa_ok( $service, 'Fritz::Service' );
};

subtest 'check dump()' => sub {
    # given
    my $service = create_service_with_scpd_data();

    # when
    my $dump = $service->dump();

    # then
    foreach my $line (split /\n/, $dump) {
	like( $line, qr/^(Fritz|  )/, 'line starts as expected' );
    }

    like( $dump, qr/^Fritz::Service/, 'class name is dumped' );
    my $service_type = $service->serviceType;
    like( $dump, qr/$service_type/, 'serviceType is dumped' );
    my $control_url = $service->controlURL;
    like( $dump, qr/$control_url/, 'controlURL is dumped' );
    my $scpd_url = $service->SCPDURL;
    like( $dump, qr/$scpd_url/, 'SCPDURL is dumped' );
    
    like( $dump, qr/^    Fritz::Action/sm, 'action is dumped' );
};


### helper methods

sub get_soap_response
{
    my $result = HTTP::Response->new( 200 );
    $result->content( get_soap_response_xml() );
    return $result;
}

sub get_unauthorized_response
{
    my $result = HTTP::Response->new( 200 );
    $result->content( get_soap_unauthenticated_xml() );
    return $result;
}

sub get_scpd_response
{
    my $result = HTTP::Response->new( 200 );
    $result->content( get_scpd_xml() );
    return $result;
}

sub pick_soap_header
{
    my ($request, $needle) = (@_);
    my $content = $request->content;
    my $regexp = "<${needle}[^>]*>([^<]+)</${needle}>"; # TODO: use an xml parser
    if ($content =~ qr/$regexp/) {
	return $1;
    }
    return undef;
}

sub authentication
{
    my $request = shift;
    my $userid = pick_soap_header($request, 'UserID');
    my $realm = pick_soap_header($request, 'Realm');
    my $nonce = pick_soap_header($request, 'Nonce');
    my $auth = pick_soap_header($request, 'Auth');

    if (defined $userid and defined $realm and defined $nonce and defined $auth) {
	my $expected_nonce = '0123456789ABCDEF';
	my $expected_realm = 'UNIT TEST REALM';
	my $expected_user = 'user';
	my $expected_pass = 'pass';
	my $expected_auth = md5_hex(
	    md5_hex (
		$expected_user
		. ':'
		. $expected_realm
		. ':'
		. $expected_pass
	    )
	    . ':'
	    . $expected_nonce
	    );

	is( $userid, $expected_user, 'auth request: userid' );
	is( $realm, $expected_realm, 'auth request: realm' );
	is( $nonce, $expected_nonce, 'auth request: nonce' );
	is( $auth, $expected_auth, 'auth request: auth' );
	return get_soap_response();
    }
    return get_unauthorized_response();
}

sub create_service_with_scpd_data
{
    my $fritz = new_ok( 'Fritz::Box', [ @_ ]);
    my $xmltree = {
	SCPDURL => [ '/SCPD' ],
	controlURL => [ '/control' ],
	serviceType => [ 'TestService' ],
    };
    my $service = new_ok( 'Fritz::Service', [ fritz => $fritz, xmltree => $xmltree ] );
    $fritz->_ua->map($fritz->upnp_url.$service->SCPDURL, get_scpd_response());
    return $service;
}

sub get_scpd_xml {
    my $SCPD_XML = <<EOF;
<?xml version="1.0"?>
<scpd xmlns="urn:dslforum-org:service-1-0">
  <actionList>
    <action>
      <name>SomeService</name>
      <argumentList>
	<argument>
	  <name>OutputArgument</name>
	  <direction>out</direction>
	  <relatedStateVariable>Argument</relatedStateVariable>
	</argument>
	<argument>
	  <name>InputArgument</name>
	  <direction>in</direction>
	  <relatedStateVariable>Argument</relatedStateVariable>
	</argument>
      </argumentList>
    </action>
  </actionList>
  <serviceStateTable>
    <stateVariable sendEvents="yes">
      <name>Argument</name>
      <dataType>string</dataType>
      <defaultValue>0815</defaultValue>
    </stateVariable>
  </serviceStateTable>
</scpd>
EOF
;
}

sub get_soap_response_xml {
    my $SOAP_XML = <<EOF;
<Envelope>
<Body>
<SomeServiceResponse>
<OutputArgument>bar</OutputArgument>
</SomeServiceResponse>
</Body>
</Envelope>
EOF
;
}

sub get_soap_unauthenticated_xml {
    my $SOAP_XML = <<EOF;
<?xml version="1.0"?>
<Envelope>
<Header>
<Challenge>
<Status>Unauthenticated</Status>
<Nonce>0123456789ABCDEF</Nonce>
<Realm>UNIT TEST REALM</Realm>
</Challenge>
</Header>
<Body>
<Fault>
<faultcode>s:Client</faultcode>
<faultstring>UPnPError</faultstring>
<detail>
<UPnPError>
<errorCode>503</errorCode>
<errorDescription></errorDescription>
</UPnPError>
</detail>
</Fault>
</Body>
</Envelope>
EOF
;
}