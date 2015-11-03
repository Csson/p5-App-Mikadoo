use 5.20.0;
use strict;
use warnings;

package App::Mikadoo::Command::MikadooConfig {

    # VERSION
    # ABSTRACT: Short intro

    use MooseX::App::Command;
    extends 'App::Mikadoo';

    use File::HomeDir 'my_dist_config';
    use Path::Tiny;
    use syntax 'qi';
    use String::Cushion;
    use experimental 'signatures';

    sub run($self) {
        defined $self->mikadoo_config_directory ? $self->handle_existing_config : $self->possibly_create_config;

    }

    sub handle_existing_config($self) {
        say sprintf "Mikadoo is configured in %s", path($self->mikadoo_config_directory, 'mikadoo.yaml')->realpath;
    }

    sub possibly_create_config($self) {

        my $reply = $self->term_get_one('Config directory does not exist. Create?', [qw/yes no/], 'yes');

        if($reply eq 'no') {
            say "Configuration not created.";
            exit;
        }

        my $cpan_author = $self->term_get_text('Your cpan username (enter for skip)');

        my @namespaces = ('Mikadoo::Template', 'App::Mikadoo::Command', (defined $cpan_author ? "Mikadoo::Template::$cpan_author" : ()));
        my $yaml_namespaces = join "\n  - " => @namespaces;

        my $config_file = path($self->mikadoo_config_directory(1), 'mikadoo.yaml');

        $config_file->spew(cushion 0, 1, qqi{
            ---
            namespaces:
              - $yaml_namespaces
        });

        say sprintf "The configuration is saved in %s", $config_file->realpath;
        say "Mikadoo is configured to look for templates in the following namespaces:";
        say join "\n" => map { "* $_" } @namespaces;


    }

    sub mikadoo_config_directory($self, $do_create = 0) { $do_create ? my_dist_config('App-Mikadoo', { create => 1 }) : my_dist_config('App-Mikadoo') }

}

1;
