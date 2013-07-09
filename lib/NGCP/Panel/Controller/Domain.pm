package NGCP::Panel::Controller::Domain;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Domain;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub dom_list :Chained('/') :PathPart('domain') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_dom_resultset_' . $c->user->auth_realm;
    my $dom_rs = $self->$dispatch_to($c);

    $c->stash(dom_rs   => $dom_rs,
              template => 'domain/list.tt');
}

sub _dom_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('domains');
}

sub _dom_resultset_reseller {
    my ($self, $c) = @_;

    return $c->model('DB')->resultset('admins')->find(
            { id => $c->user->id, } )
        ->reseller
        ->domain_resellers
        ->search_related('domain');
}

sub root :Chained('dom_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('dom_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {

        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->model('DB')->resultset('voip_domains')
                    ->create({domain => $form->value->{domain}});
                my $new_dom = $c->stash->{dom_rs}
                    ->create({domain => $form->value->{domain}});

                if( $c->user->auth_realm eq 'reseller' ) {
                    my $reseller = $c->model('DB')->resultset('admins')
                        ->find($c->user->id)->reseller;
                    $new_dom->create_related('domain_resellers', {
                        reseller => $reseller
                    });
                }
            });
        } catch ($e) {
            $c->flash(messages => [{type => 'error', text => 'Creation of Domain failed!'}]);
            $c->log->error("Create failed: $e");
            $c->response->redirect($c->uri_for());
            return;
        }

        $self->_sip_domain_reload;
        $c->flash(messages => [{type => 'success', text => 'Domain successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('/domain/dom_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $domain_id) = @_;

    unless($domain_id && $domain_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid domain id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{dom_rs}->find($domain_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Domain does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(provisioning_domain_result => $c->model('DB')
        ->resultset('voip_domains')
        ->find({domain => $res->domain}) );

    $c->stash(domain        => {$res->get_columns},
              domain_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{domain},
        action => $c->uri_for($c->stash->{domain}->{id}, 'edit'),
    );
    if($posted && $form->validated) {

        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->stash->{'domain_result'}->update({
                    domain => $form->value->{domain},
                });
                $c->stash->{'provisioning_domain_result'}->update({
                    domain => $form->value->{domain},
                });
            });
        } catch ($e) {
            $c->flash(messages => [{type => 'error', text => 'Update of Domain failed!'}]);
            $c->log->error("Update failed: $e");
            $c->response->redirect($c->uri_for());
            return;
        }

        $self->_sip_domain_reload;

        $c->flash(messages => [{type => 'success', text => 'Domain successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->model('DB')->schema->txn_do( sub {
            $c->stash->{'domain_result'}->delete;
            $c->stash->{'provisioning_domain_result'}->delete;
        });
    } catch ($e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed!'}]);
        $c->log->error("Delete failed: $e");
        $c->response->redirect($c->uri_for());
        return;
    }

    $self->_sip_domain_reload;

    $c->flash(messages => [{type => 'success', text => 'Domain successfully deleted!'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('dom_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{dom_rs};

    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "domain"],
                 ["domain"]]);
    $c->detach( $c->view("JSON") );
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{provisioning_domain_id} = $c->stash
        ->{provisioning_domain_result}->id;

    $self->load_preference_list($c);
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_base :Chained('base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});
    my $domain_name = $c->stash->{domain}->{domain};
    $c->stash->{provisioning_domain_id} = $c->model('DB')
        ->resultset('voip_domains')
        ->single({domain => $domain_name})->id;

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_dom_preferences')
        ->search({
            attribute_id => $pref_id,
            domain_id => $c->stash->{provisioning_domain_id}
        });
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);
    
    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({dom_pref => 1})
        ->all;

    my $pref_rs = $c->stash->{preference};

    NGCP::Panel::Utils::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/domain/preferences', [$c->req->captures->[0]]),
        edit_uri => $c->uri_for_action('/domain/preferences_edit', $c->req->captures),
    );
}

sub load_preference_list :Private {
    my ($self, $c) = @_;
    
    my $dom_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                domain => $c->stash->{domain}->{domain}
            },{
                prefetch => {'voip_dom_preferences' => 'domain'},
            });
        
    my %pref_values;
    foreach my $value($dom_pref_values->all) {
    
        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_dom_preferences->all
        ];
    }

    NGCP::Panel::Utils::load_preference_list( c => $c,
        pref_values => \%pref_values,
        dom_pref => 1,
    );
}

sub _sip_domain_reload {
    my ($self) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch("proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 dom_list

basis for the domain controller

=head2 root

=head2 create

Provide a form to create new domains. Handle posted data and create domains.

=head2 search

obsolete

=head2 base

Fetch a domain by its id.

Data that is put on stash: domain, domain_result

=head2 edit

probably obsolete

=head2 delete

deletes a domain (defined in base)

=head2 ajax

Get domains and output them as JSON.

=head2 preferences

Show a table view of preferences.

Data that is put on stash: provisioning_domain_id

=head2 preferences_base

Get details about one preference for further editing.

Data that is put on stash: preference_meta, provisioning_domain_id, preference, preference_values

=head2 preferences_edit

Use a form for editing one preference. Execute the changes that are posted.

Data that is put on stash: edit_preference, form

=head2 load_preference_list

Retrieves and processes a datastructure containing preference groups, preferences and their values, to be used in rendering the preference list.

Data that is put on stash: pref_groups

=head2 _sip_domain_reload

Ported from ossbss

reloads domain cache of sip proxies

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
