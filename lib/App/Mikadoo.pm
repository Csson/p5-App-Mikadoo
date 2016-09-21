use 5.20.0;
use strict;
use warnings;

package App::Mikadoo;
use MooseX::App qw/Color/;

# VERSION
# ABSTRACT: Short intro

use Term::UI;
use Term::ReadLine;
use Syntax::Keyword::Junction 'none' => { -as => 'jnone' }, 'any' => { -as => 'jany' };
use PerlX::Maybe;
use MooseX::AttributeShortcuts;
use Mojo::Template;
use Path::Tiny;
use Types::Path::Tiny -types;
use Types::Standard -types;
use syntax 'qi';
use File::HomeDir qw/my_dist_config/;
use File::ShareDir::Tarball qw/dist_dir/;
use YAML::Tiny;
use experimental qw/signatures postderef/;

{
    my @namespaces = my_dist_config('App-Mikadoo') && path(my_dist_config('App-Mikadoo'))->exists
                   ? YAML::Tiny->read(path(my_dist_config('App-Mikadoo'), 'mikadoo.yaml'))->[0]{'namespaces'}->@*
                   : ('App::Mikadoo::Command', 'Mikadoo::Template')
                   ;
    
    app_namespace(@namespaces);
}

option location => (
    is => 'ro',
    isa => Path,
    coerce => 1,
    default => sub { '.' },
);
option perl_version => (
    is => 'rw',
    predicate => 1,
);
option experimentals => (
    is => 'rw',
    isa => ArrayRef,
    traits => ['Array'],
    default => sub { [] },
    handles => {
        all_experimentals => 'elements',
        has_experimentals => 'count',
    },
);
option namespace => (
    is => 'ro',
    lazy => 1,
    predicate => 1,
    builder => 1,
);
option namespace_under => (
    is => 'rw',
    predicate => 1,
);
option namespace_separator => (
    is => 'rw',
    default => '::',
);
has term => (
    is => 'ro',
    default => sub { Term::ReadLine->new('mikadoo') },
);
has dist => (
    is => 'rw',
    isa => Str,
    predicate => 1,
);


sub _build_namespace($self) {
    return if !$self->has_namespace_under;
    my $namespace_under = $self->namespace_under;

    my $location = $self->location;
    my @paths = ($location->realpath =~ s{^.*/([^/]*)$}{$1}rg); # g for sublimetext

    LIB_SEARCH:
    while($location = $location->parent) {

        if($location->realpath->stringify =~ m{/$namespace_under$}) {
            last LIB_SEARCH;
        }
        elsif($location->realpath eq '/') {
            die sprintf "Can't find $namespace_under/ directory in path <%s>", $self->location->realpath;
            last LIB_SEARCH;
        }
        else {
            unshift @paths => ($location->realpath =~ s{^.*/([^/]*)$}{$1}rg); # g for sublimetext
        }
    }

    if(scalar @paths) {
        return join '::' => @paths;
    }

}

sub perl_version_short($self) {
    return undef if !$self->has_perl_version;
    return $self->perl_version =~ s{^5\.(\d+)(?:\..*)$}{$1}r;
}

sub term_get_text($self, $prompt, $options = {}) {

    my @prompts = ("\n$prompt");
    if(exists $options->{'shortcuts'} && scalar $options->{'shortcuts'}->@*) {
        my $longest = (sort { length $b->{'key'} <=> length $a->{'key'} } $options->{'shortcuts'}->@*)[0];
        my $length = length $longest->{'key'};

        for my $shortcut ($options->{'shortcuts'}->@*) {
            push @prompts => sprintf "%-${length}s : %s", $shortcut->{'key'}, $shortcut->{'text'};
        }
    }
    say join "\n" => @prompts;
    return $self->term->get_reply(prompt => '');
}

sub term_get_one($self, $header, $choices, $default = undef, $prompt = undef) {

    ($prompt, $choices) = $self->_prepare_term($choices, $default, $prompt);

    my $reply = $self->term->get_reply(
              print_me => "\n$header",
              choices => $choices,
        maybe default => $default,
              prompt => $prompt,
    );

    return $reply;
}

sub term_get_multi($self, $header, $choices, $default = [], $prompt = undef) {

    ($prompt, $choices) = $self->_prepare_term($choices, $default, $prompt);

    my $thing = [$self->term->get_reply(
              print_me => "\n$header",
              choices => $choices,
              prompt => $prompt,
              multi => 1,
              default => $default,
    )];
    return $thing;
}

sub ask_perl_version($self, $options = { }) {
    $self->perl_version($self->term_choose_perl_version($options));
}
sub ask_experimentals($self) {
    $self->experimentals($self->term_choose_experimentals);
}

sub term_choose_perl_version($self, $options = { }) {
    my $from = $options->{'from'} // 6;
    my $to = $options->{'to'} // 22;
    my $default = $options->{'default'} // 20;
    return $self->term_get_one('Choose perl version', [map { "5.$_.0" } grep { $_ % 2 == 0 } ($from..$to)], "5.$default.0");
}

sub term_choose_experimentals($self, $default = [qw/postderef signatures/]) {
    my $possible_experimentals = [sort qw/
        smartmatch
        lexical_topic
        lexical_subs
        regex_sets
        signatures
        postderef
        refaliasing
        const_attr
        re_strict
        bitwise
    /];

    my $experimentals = $self->term_get_multi('Choose exeperimentals', $possible_experimentals, $default);

}

sub render($self, $template, $destination, $options = {}) {
    $options->{'remove_leading_whitespace'} //= 1;

    my $templates = path(dist_dir($self->dist), 'templates');

    my $result_template = $templates->child($template)->slurp_utf8;
    my $rendered = Mojo::Template->new->render($result_template, $self);

    if($options->{'remove_leading_whitespace'}) {
        $rendered = qqi{$rendered};
    }

    if(!$destination->exists || $self->term_get_one("Render destination <$destination> exists. Overwrite?", [qw/yes no/], 'no') eq 'yes') {
        $destination->spew_utf8($rendered);
        say "<$destination> created.";
    }
    else {
        say "<$destination> already existed. Did not overwrite.";
    }
    return $self;
}

# @paths should be to filenames (not directories).
sub ensure_parents_exist($self, @paths) {
    for my $path (@paths) {
        if($path->exists) {
            say sprintf 'Path already exists: <%s>', $path;
        }

        if(!$path->parent->exists) {
            say sprintf 'Creating directory: %s', $path->parent;
            $path->parent->mkpath;
        }
    }
}

sub _prepare_term($self, $choices, $default = undef, $prompt = undef) {

    # For multi answer questions $default is an array ref
    if(ref $default eq 'ARRAY') {
        for my $def_index (0 .. scalar @$default - 1) {
            if(jnone(@$choices) eq $default->[$def_index]) {
                die sprintf "<%s> not in <%s>", $default->[$def_index], join ', ' => @$choices;
            }
        }
     }
    else {
        if(defined $default && jnone(@$choices) eq $default) {
            die sprintf "<%s> not in <%s>", $default, join ', ' => @$choices;
        }
    }

    my $default_in_prompt = ref $default eq 'ARRAY' && scalar @$default ? sprintf '[default: %s]', join (', ' => @$default)
                          : defined $default                            ? "[default: $default]"
                          :                                               undef
                          ;

    if(ref $prompt eq 'ARRAY') {
        $prompt = join "\n" => $prompt;
    }
    $prompt = join (' ' => ($prompt || (), $default_in_prompt || ()));

    return ($prompt, $choices);

}

1;

__END__

=pod

=head1 SYNOPSIS

    use App::Mikadoo;

=head1 DESCRIPTION

App::Mikadoo is ...

=head1 SEE ALSO

=cut
