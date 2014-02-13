package NGCP::Panel::Form::Subscriber::TrustedSource;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use Data::Validate::IP qw/is_ipv4 is_ipv6/;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'src_ip' => (
    type => 'Text',
    label => 'Source IP',
    required => 1,
);

has_field 'protocol' => (
    type => 'Select',
    label => 'Protocol',
    required => 1,
    options => [
        { label => 'UDP', value => 'UDP' },
        { label => 'TCP', value => 'TCP' },
        { label => 'TLS', value => 'TLS' },
        { label => 'ANY', value => 'ANY' },
    ],
);

has_field 'from_pattern' => (
    type => 'Text',
    label => 'From Pattern',
    required => 0,
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/src_ip protocol from_pattern/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_src_ip {
    my ($self, $field) = @_;

    my ($ip, $net) = split /\//, $field->value;
    if(is_ipv4($ip)) {
        return 1 unless(defined $net);
        unless($net->is_int && $net >= 0 && $net <= 32) {
            $field->add_error("Invalid IPv4 network portion, must be 0 <= net <= 32");
        }
    } elsif(is_ipv6($ip)) {
        return 1 unless(defined $net);
        unless($net->is_int && $net >= 0 && $net <= 128) {
            $field->add_error("Invalid IPv4 network portion, must be 0 <= net <= 128");
        }
    } else {
        $field->add_error("Invalid IPv4 or IPv6 address, must be valid address with optional /net suffix."); 
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
