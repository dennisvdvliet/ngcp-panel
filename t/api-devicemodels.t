use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

#my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my $uri = 'https://192.168.56.7:1444';

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{ API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

# OPTIONS tests
{
    
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/pbxdevicemodels/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; model=http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodels", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $reseller_id = 1;

# collection test
my $firstmodel = undef;
my @allmodels = ();
{
    # create 6 new billing models
    my %models = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/pbxdevicemodels/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            "model"=>"ATA11$i",
            #3.7relative tests
            #"bootstrap_method"=>"http",
            #"bootstrap_config_http_sync_uri"=>"http=>//[% client.ip %]/admin/resync",
            #"bootstrap_config_http_sync_params"=>"[% server.uri %]/$MA",
            #"bootstrap_config_http_sync_method"=>"GET",
            "reseller_id"=>"$reseller_id",
            "vendor"=>"Cisco",
            "linerange"=>[
                {
                    "keys"=>[
                        {"y"=>"390","labelpos"=>"left","x"=>"510"},
                        {"y"=>"350","labelpos"=>"left","x"=>"510"}
                    ],
                    "can_private"=>"1",
                    "can_shared"=>"0",
                    "can_blf"=>"0",
                    "name"=>"Phone Ports",
                    "id"=>1311
                }
            ]
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test billing model $i");
        $models{$res->header('Location')} = 1;
        push @allmodels, $res->header('Location');
        $firstmodel = $res->header('Location') unless $firstmodel;
    }

    # try to create model without reseller_id
    $req = HTTP::Request->new('POST', $uri.'/api/pbxdevicemodels/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create model without reseller_id");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");

    # try to create model with empty reseller_id
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
        reseller_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create model with empty reseller_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");

    # try to create model with invalid reseller_id
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
        reseller_id => 99999,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create model with invalid reseller_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'reseller_id'/, "check error message in body");

    # TODO: check for wrong values in prepaid, fees etc

    # iterate over contracts collection to check next/prev links and status
    my $nexturi = $uri.'/api/pbxdevicemodels/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch model page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok($collection->{total_count} > 0, "check 'total_count' of collection");

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, "check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, "check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, "check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, "check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, "check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok((ref $collection->{_links}->{'ngcp:pbxdevicemodels'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:pbxdevicemodels'} eq "HASH"), "check if 'ngcp:pbxdevicemodels' is array/hash-ref");

        # remove any entry we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:pbxdevicemodels'} eq "HASH") {
            # these relations are only there if we have zones/fees, which is not the case with an empty model
            #ok(exists $collection->{_embedded}->{'ngcp:pbxdevicemodels'}->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
            #ok(exists $collection->{_embedded}->{'ngcp:pbxdevicemodels'}->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");
            delete $models{$collection->{_links}->{'ngcp:pbxdevicemodels'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:pbxdevicemodels'} }) {
                delete $models{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:pbxdevicemodels'} }) {
            # these relations are only there if we have zones/fees, which is not the case with an empty model
            #ok(exists $collection->{_embedded}->{'ngcp:pbxdevicemodels'}->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
                #ok(exists $c->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
                #ok(exists $c->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");

                delete $models{$c->{_links}->{self}->{href}};
            }
        }
             
    } while($nexturi);

    is(scalar(keys %models), 0, "check if all test billing models have been found");
}

# test model item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstmodel);
    $res = $ua->request($req);
    is($res->code, 200, "check options on item");
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    my $opts = JSON::from_json($res->decoded_content);
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS PUT PATCH )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( POST DELETE )) {
        ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");
    }

    $req = HTTP::Request->new('GET', $uri.'/'.$firstmodel);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one contract item");
    my $model = JSON::from_json($res->decoded_content);
    ok(exists $model->{reseller_id} && $model->{reseller_id}->is_int, "check existence of reseller_id");
    ok(exists $model->{handle}, "check existence of handle");
    ok(exists $model->{name}, "check existence of name");
    
    # PUT same result again
    my $old_model = { %$model };
    delete $model->{_links};
    delete $model->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstmodel);
    
    # check if it fails without content type
    $req->remove_header('Content-Type');
    $req->header('Prefer' => "return=minimal");
    $res = $ua->request($req);
    is($res->code, 415, "check put missing content type");

    # check if it fails with unsupported content type
    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    is($res->code, 415, "check put invalid content type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json');

    # check if it fails with invalid Prefer
    $req->header('Prefer' => "return=invalid");
    $res = $ua->request($req);
    is($res->code, 400, "check put invalid prefer");


    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=representation");

    # check if it fails with missing body
    $res = $ua->request($req);
    is($res->code, 400, "check put no body");

    # check if put is ok
    $req->content(JSON::to_json($model));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_model = JSON::from_json($res->decoded_content);
    is_deeply($old_model, $new_model, "check put if unmodified put returns the same");

    # check if we have the proper links
    # TODO: fees, reseller links
    #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstmodel);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    my $t = time;
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => 'patched name '.$t } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched model item");
    my $mod_model = JSON::from_json($res->decoded_content);
    is($mod_model->{name}, "patched name $t", "check patched replace op");
    is($mod_model->{_links}->{self}->{href}, $firstmodel, "check patched self link");
    is($mod_model->{_links}->{collection}->{href}, '/api/pbxdevicemodels/', "check patched collection link");
    

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef reseller");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid reseller");

    # TODO: invalid handle etc
}

done_testing;

# vim: set tabstop=4 expandtab:
