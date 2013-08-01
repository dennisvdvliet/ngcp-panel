package NGCP::Panel::Controller::NCOS;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::NCOS::ResellerLevel;
use NGCP::Panel::Form::NCOS::AdminLevel;
use NGCP::Panel::Form::NCOS::Pattern;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Datatables;

use HTML::FormHandler;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub levels_list :Chained('/') :PathPart('ncos') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $dispatch_to = '_levels_resultset_' . $c->user->auth_realm;
    my $levels_rs = $self->$dispatch_to($c);
    $c->stash(levels_rs => $levels_rs);

    $c->stash->{level_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'reseller.name', search => 1, title => 'Reseller' },
        { name => 'level', search => 1, title => 'Level Name' },
        { name => 'mode', search => 1, title => 'Mode' },
        { name => 'description', search => 1, title => 'Description' },
    ]);

    $c->stash(template => 'ncos/list.tt');
}

sub _levels_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('ncos_levels');
    return $rs;
}

sub _levels_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->ncos_levels;
    return $rs;
}

sub root :Chained('levels_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('levels_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{levels_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{level_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('levels_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $level_id) = @_;

    unless($level_id && $level_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid NCOS level id detected'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
    }

    my $res = $c->stash->{levels_rs}->find($level_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'NCOS level does not exist'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
    }
    $c->stash(level_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $level = $c->stash->{level_result};
    my $params = { $level->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::NCOS::AdminLevel->new;
    } else {
        $form = NGCP::Panel::Form::NCOS::ResellerLevel->new;
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $form->values->{reseller_id} = $form->values->{reseller}{id};
            delete $form->values->{reseller};
            $level->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => 'NCOS level successfully updated'}]);
        } catch($e) {
            $c->log->error("failed to update ncos level: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update NCOS level'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/ncos'));
    }

    $c->stash(
        close_target => $c->uri_for,
        edit_flag => 1,
        form => $form,
    );
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{level_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'NCOS level successfully deleted'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Failed to delete NCOS level'}]);
        $c->log->error("failed to delete ncos level: $e");
    };
    $c->response->redirect($c->uri_for());
}

sub create :Chained('levels_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::NCOS::AdminLevel->new;
    } else {
        $form = NGCP::Panel::Form::NCOS::ResellerLevel->new;
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $level = $c->stash->{levels_rs};
            unless($c->user->is_superuser) {
                $form->values->{reseller}{id} = $c->user->reseller_id;
            }
            $level->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => 'NCOS level successfully created'}]);
        } catch($e) {
            $c->log->error("failed to create ncos level: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create NCOS level'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/ncos'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form,
    );
}

sub pattern_list :Chained('base') :PathPart('pattern') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $pattern_rs = $c->stash->{level_result}->ncos_pattern_lists;
    $c->stash(pattern_rs => $pattern_rs);
    $c->stash(pattern_base_uri =>
        $c->uri_for_action("/ncos/pattern_root", [$c->req->captures->[0]]));

    $c->stash->{pattern_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'pattern', search => 1, title => 'Pattern' },
        { name => 'description', search => 1, title => 'Description' },
    ]);
    
    my $local_ac_form = HTML::FormHandler::Model::DBIC->new(field_list => [
        local_ac => { type => 'Boolean', label => 'Include local area code'},
        save => { type => 'Submit', value => 'Set', element_class => ['btn']},
        ],
        'widget_wrapper' => 'Bootstrap',
        form_element_class => ['form-horizontal', 'ngcp-quickform'],
    );
    $local_ac_form->process(
        posted => ($c->request->method eq 'POST') && defined $c->req->params->{local_ac},
        params => $c->request->params,
        item   => $c->stash->{level_result}
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $local_ac_form,
        fields => {},
        back_uri => $c->req->uri,
    );
    $c->stash(local_ac_form => $local_ac_form);
    if($local_ac_form->validated) {
        try {
            $c->stash->{pattern_rs}->first->update({
                local_ac => $local_ac_form->values->{local_ac},
            });
            $c->flash(messages => [{type => 'success', text => 'Successfully updated NCOS pattern'}]);
        } catch($e) {
            $c->log->error("failed to update local-ac for ncos: $e");
            $c->flash(messages => [{type => 'success', text => 'Successfully updated NCOS pattern'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(template => 'ncos/pattern_list.tt');
}

sub pattern_root :Chained('pattern_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub pattern_ajax :Chained('pattern_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{pattern_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{pattern_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub pattern_base :Chained('pattern_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pattern_id) = @_;

    unless($pattern_id && $pattern_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid NCOS pattern id detected'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    my $res = $c->stash->{pattern_rs}->find($pattern_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'NCOS pattern does not exist'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }
    $c->stash(pattern_result => $res);
}

sub pattern_edit :Chained('pattern_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOS::Pattern->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $c->stash->{pattern_result},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{pattern_result}->update($form->values);
            $c->flash(messages => [{type => 'success', text => 'NCOS pattern successfully updated'}]);
        } catch($e) {
            $c->log->error("failed to update ncos pattern: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update NCOS pattern'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(
        close_target => $c->stash->{pattern_base_uri},
        form => $form,
        edit_flag => 1
    );
}

sub pattern_delete :Chained('pattern_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{pattern_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'NCOS pattern successfully deleted'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->log->error("failed to delete ncos pattern: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to delete NCOS pattern'}]);
    };
    NGCP::Panel::Utils::Navigation::back_or($c->stash->{pattern_base_uri});
}

sub pattern_create :Chained('pattern_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOS::Pattern->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{pattern_rs}->create($form->values);
            $c->flash(messages => [{type => 'success', text => 'NCOS pattern successfully created'}]);
        } catch($e) {
            $c->log->error("failed to create ncos pattern: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create NCOS pattern'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{pattern_base_uri});
    }

    $c->stash(
        close_target => $c->stash->{pattern_base_uri},
        form => $form,
        create_flag => 1
    );
}


__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::NCOS - manage NCOS levels/patterns

=head1 DESCRIPTION

Show/Edit/Create/Delete NCOS Levels.

Show/Edit/Create/Delete Number patterns.

=head1 METHODS

=head2 auto

Grants access to admin and reseller role.

=head2 levels_list

Basis for billing.ncos_levels.

=head2 root

Display NCOS Levels through F<ncos/list.tt> template.

=head2 ajax

Get billing.ncos_levels from db and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a billing.ncos_levels row from the database by its id.
The resultset is exported to stash as "level_result".

=head2 edit

Show a modal to edit the NCOS Level determined by L</base>.

=head2 delete

Delete the NCOS Level determined by L</base>.

=head2 create

Show modal to create a new NCOS Level using the form
L<NGCP::Panel::Form::NCOSLevel>.

=head2 pattern_list

Basis for billing.ncos_pattern_list.
Fetches all patterns related to the level determined by L</base> and stashes
the resultset under "pattern_rs".

=head2 pattern_root

Display NCOS Number Patterns through F<ncos/pattern_list.tt> template.

=head2 pattern_ajax

Get patterns from db using the resultset from L</pattern_list> and
output them as JSON. The format is meant for parsing with datatables.

=head2 pattern_base

Fetch a billing.ncos_pattern_list row from the database by its id.
The resultset is exported to stash as "pattern_result".

=head2 pattern_edit

Show a modal to edit the Number Pattern determined by L</pattern_base>.

=head2 pattern_delete

Delete the Number Pattern determined by L</pattern_base>.

=head2 pattern_create

Show modal to create a new Number Pattern for the current Level using the form
L<NGCP::Panel::Form::NCOSPattern>.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
