package NGCP::Panel::Controller::API::SoundSetsItem;
use Sipwise::Base;
use namespace::sweep;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API::SoundSets';

class_has('resource_name', is => 'ro', default => 'soundsets');
class_has('dispatch_path', is => 'ro', default => '/api/soundsets/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-soundsets');

class_has(@{ __PACKAGE__->get_journal_query_params() });

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        @{ __PACKAGE__->get_journal_action_config(__PACKAGE__->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)],
        }) }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundset => $item);

        my $hal = $self->hal_from_item($c, $item);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
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
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c, 
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundset => $item);
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        
        my $hal = $self->hal_from_item($c, $item, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $item, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundset => $item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        
        my $hal = $self->hal_from_item($c, $item, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $item, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundset => $item);

        if($item->contract_id) {
            my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'contract_sound_set',
            );
            $pref_rs->search({ value => $item->id })->delete;
        }

        foreach my $p(qw/usr dom peer/) {
            $c->model('DB')->resultset("voip_".$p."_preferences")->search({
                'attribute.attribute' => 'sound_set',
                value => $item->id,
            },{
                join => 'attribute',
            })->delete_all; # explicit delete_all, otherwise query fails
        }
        
        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            return $self->hal_from_item($c, $item); });
        
        $item->delete;

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub item_base_journal :Journal {
    my $self = shift @_;
    return $self->handle_item_base_journal(@_);
}
    
sub journals_get :Journal {
    my $self = shift @_;
    return $self->handle_journals_get(@_);
}

sub journalsitem_get :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_get(@_);
}

sub journals_options :Journal {
    my $self = shift @_;
    return $self->handle_journals_options(@_);
}

sub journalsitem_options :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_options(@_);
}

sub journals_head :Journal {
    my $self = shift @_;
    return $self->handle_journals_head(@_);
}

sub journalsitem_head :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_head(@_);
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
