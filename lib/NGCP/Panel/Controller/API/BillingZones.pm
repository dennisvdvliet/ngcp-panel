package NGCP::Panel::Controller::API::BillingZones;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Form::BillingZone qw();
use Path::Tiny qw(path);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';
with 'NGCP::Panel::Role::API::BillingZones';

class_has('resource_name', is => 'ro', default => 'billingzones');
class_has('dispatch_path', is => 'ro', default => '/api/billingzones/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-billingzones');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $zones = $c->model('DB')->resultset('billing_zones');
        if($c->request->query_parameters->{billing_profile_id}) {
            $zones = $zones->search({ 
                billing_profile_id => $c->request->query_parameters->{billing_profile_id},
            });
        };

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $zones = $zones->search({ 
                'billing_profile.reseller_id' => $c->user->reseller_id 
            }, {
                join => 'billing_profile',
            });
        } else {
            $zones = $zones->search({ 
                'billing_profile.reseller_id' => $c->user->contract->contact->reseller_id,
            }, {
                join => 'billing_profile',
            });
        }
        my $total_count = int($zones->count);
        $zones = $zones->search(undef, {
            page => $page,
            rows => $rows,
        });
        my (@embedded, @links);
        my $form = NGCP::Panel::Form::BillingZone->new;
        for my $zone ($zones->all) {
            push @embedded, $self->hal_from_zone($c, $zone, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $zone->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));

        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $rname = $self->resource_name;
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-$rname)"|rel="item $1"|;
                s/rel=self/rel="collection self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $reseller_id;
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $reseller_id = $c->user->reseller_id;
        } else {
            $reseller_id = $c->user->contract->contact->reseller_id;
        }

        my $form = NGCP::Panel::Form::BillingZone->new;
        my $billing_profile_id = $resource->{billing_profile_id} // undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        $resource->{billing_profile_id} = $billing_profile_id;

        my $profile = $schema->resultset('billing_profiles')->find($resource->{billing_profile_id});
        unless($profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }
        if($c->user->roles ne "admin" && $profile->reseller_id != $reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }

        my $zone;
        try {
            $zone = $profile->billing_zones->create($resource);
        } catch($e) {
            $c->log->error("failed to create billing zone: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billing zone.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $zone->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab: