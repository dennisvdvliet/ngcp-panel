package NGCP::Panel::View::SVG;

use Sipwise::Base;
use NGCP::Panel::Utils::I18N;

use strict;
extends 'Catalyst::View::TT';



__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    WRAPPER => '',
    FILTERS => {},
    ABSOLUTE => 0,
    expose_methods => [qw/translate_form/],
);
#copy-paste from html, method is too small to move it to separate class
sub translate_form {
    my $self = shift;
    NGCP::Panel::Utils::I18N->translate_form(@_);
}

sub process{
    my ( $self, $c ) = @_;
    #$c->res->content_type("image/svg+xml");
    $self->{template}->context->define_vmethod(
        hash => get_column => sub {
            my($item,$col) = @_;
            if('HASH' eq ref $item){
                return $item->{$col};
            }
        }
    );

    if($c->stash->{VIEW_NO_TT_PROCESS}) {
        $c->log->debug("VIEW_NO_TT_PROCESS=".$c->stash->{VIEW_NO_TT_PROCESS}.";\n");
        
        my $output = $self->getTemplateContent($c);

        $c->log->debug("output is empty=".($output?0:1).";\n");
        
        $c->response->body($output);
        #$self->{template}->{LOAD_TEMPLATES}->load();
    } else{
        $c->log->debug("VIEW INVOICE TEMPLATE:just send to process;\n");
        $self->SUPER::process($c) ;
    }
    return 1;
}
sub getTemplate{
    my ( $self, $c, $template ) = @_;
    if(defined $template){
        $c and $c->log->debug("getTemplate: template=$template;");
    }
    $c and $template ||= ( $c->stash->{template} ||  $c->action . $self->config->{TEMPLATE_EXTENSION} );
    $c and $c->log->debug("getTemplate: template=$template;");
    return $template;
}
#method is necessary to apply APP specific template configurations, e.g. path, tt file extensions etc
#may be moved to main view class, but as on template_invoice experiments stage it would be ok to leave it in separated class
sub getTemplateContent{
    my ( $self, $c, $template ) = @_;
   
    my $r = $self->{template}->context->insert($self->getTemplate($c,$template));
    use utf8;
    utf8::decode($r);
    return $r;
}
sub getTemplateProcessed{
    my ( $self, $c, $template, $stash ) = @_;
    $self->{template}->context->define_vmethod(
        hash => get_column => sub {
            my($item,$col) = @_;
            if('HASH' eq ref $item){
                return $item->{$col};
            }
        }
    );
    #$c->log->debug("getTemplateProcessed: template=$template;");
    #my $result = $self->{template}->context->process($template, $stash);
    #$c->log->debug("getTemplateProcessed: result=$result;");
    
    #return $result
    return $self->{template}->context->process($template, $stash);
}
sub getTemplateVars{
    my ( $self, $c, $template,$vars ) = @_;
    #$vars //= {};
    #
    #$template = \'
    #[%var = "qqq"%]
    #
    #';
    #
    #my $text = '';
    #my $stc = {};
    #$vars->{template_import} ||= $stc;
    #my $importold = $Template::Stash::HASH_OPS->{ import } if defined $Template::Stash::HASH_OPS->{ import };
    #$Template::Stash::HASH_OPS->{ import } = sub { $stc = $_[0]; };
    #$self->{template}->context->define_vmethod(
    #    hash => import => sub {
    #        my($item,$col) = @_;
    #        if('HASH' eq ref $item){
    #            return $item->{$col};
    #        }
    #    }
    #);
    #$self->{template}->process($template,$vars,\$text);
    #$Template::Stash::HASH_OPS->{ import } = $importold if defined $importold;
    #
    ##$subject ||= $stc->get('subject');
    ##$type    ||= $stc->get('mimetype');
    ##$from    ||= $stc->get('from');
    #$Data::Dumper::Maxdepth = 1;
    #use irka;
    #use Data::Dumper;
    #irka::loglong(Dumper($stc));
    ##$c->log->debug("var=".$stc->get('var').";");
    #return $stc;
}

1;
