package NGCP::Panel::Widget::Plugin::ResellerTopMenuSettings;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_topmenu_settings.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'topmenu_widgets',
);

around handle => sub {
    my ($foo, $self, $c) = @_;
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user->roles eq 'reseller'
    );
    return;
}

1;
# vim: set syntax=perl tabstop=4 expandtab:
