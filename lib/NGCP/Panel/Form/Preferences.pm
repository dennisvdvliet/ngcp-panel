package NGCP::Panel::Form::Preferences;

use HTML::FormHandler::Moose;
use Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;
use HTML::Entities qw/encode_entities/;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has 'pref_rs' => (is => 'rw');
has 'readonly' => (is   => 'rw',
                   isa  => 'Int',
                   default => 0,);

sub create_my_fields {
    my $self = shift;
    
    my @field_list = ();
    
    foreach my $preference ($self->pref_rs->all) {
        $self->create_one_field($preference);
        push @field_list, $preference->attribute;
    }
    
    $self->create_structure(\@field_list);
}

sub create_structure {
    my $self = shift;
    my $field_list = shift;
    
    has_block 'fields' => (
        tag => 'div',
        #class => [qw/accordion/],
        render_list => $field_list,
    );
}

sub create_one_field {
    my $self = shift;
    my $preference = shift;
    
    my $field_type;
    if($preference->data_type eq "string") {
        $field_type = "Text";
    } elsif ($preference->data_type eq "boolean") {
        $field_type = "Boolean";
    } else {
        $field_type = "Boolean";
    }
    if($preference->max_occur == 0) {
        $field_type = "Select";
    }
    
    has_field $preference->attribute => (
        type => $field_type,
        element_attr => { title => encode_entities($preference->description),
            $self->readonly ? (readonly => 1) : (), },
    );
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'actions' => (
    tag => 'div',
    #class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
