package NGCP::Panel::Widget::Plugin::AdminResellerOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_reseller_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 10,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    $c->stash(
        resellers => $c->model('DB')->resultset('resellers')->search_rs({
            status => { '!=' => 'terminated' },
        }),
        domains => $c->model('DB')->resultset('domain_resellers')->search_rs({}),
        customers => $c->model('DB')->resultset('contracts')->search_rs({
            status => { '!=' => 'terminated' },
            'product.class' => { 'not in' => [ 'reseller', 'sippeering', 'pstnpeering' ] },
        }, {
            join => { 'billing_mappings' => 'product' },
        }),
        subscribers => $c->model('DB')->resultset('voip_subscribers')->search_rs({
            status => { '!=' => 'terminated' },
        }),
    );
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user->roles eq 'admin' &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
