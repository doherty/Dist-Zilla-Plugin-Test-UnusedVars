use 5.008;
use strict;
use warnings;

package Dist::Zilla::Plugin::Test::UnusedVars;
# ABSTRACT: Release tests for unused variables
# VERSION
use Path::Tiny;
use Moose;
use Data::Section -setup;
with qw(
    Dist::Zilla::Role::FileGatherer
    Dist::Zilla::Role::TextTemplate
);

has files => (
    is  => 'ro',
    isa => 'Maybe[ArrayRef[Str]]',
    predicate => 'has_files',
);

has ignore_vars => (
    is  => 'ro',
    isa => 'Maybe[ArrayRef[Str]]',
    predicate => 'has_ignore_vars',
);

=for Pod::Coverage *EVERYTHING*

=cut

sub mvp_multivalue_args { return qw/ files ignore_vars / }
sub mvp_aliases { return { file => 'files', ignore_var => 'ignore_vars' } }

sub _normalize_path {
    path($_[0])->relative('lib')->stringify;
}

sub gather_files {
    my $self = shift;
    my $file = 'xt/release/unused-vars.t';

    my @files;
    @files = map { _normalize_path( $_) } @{ $self->files }
      if $self->has_files;

    # accomodate file specific ignored vars
    my %ignore_vars;
    if ( $self->has_ignore_vars ) {
        for my $var_spec ( @{ $self->ignore_vars } ) {
            my ( $file, $var ) = $var_spec =~ /^(?:(.*):)?(.*)$/;
            my $key = defined $file ? _normalize_path( $file ) : '';
            push @{ $ignore_vars{$key} ||= [] }, $var;
        }
    }

    # add globally ignored files to each file's list.
    if ( defined $ignore_vars{''} ) {
        push @{ $ignore_vars{$_} ||= [] }, @{ $ignore_vars{''} }
          for @files;
    }

    require Dist::Zilla::File::InMemory;
    $self->add_file(
        Dist::Zilla::File::InMemory->new({
            name    => $file,
            content => $self->fill_in_string(
                ${ $self->section_data($file) },
                {
                    has_files => $self->has_files,
                    files => \@files,
                    has_ignore_vars => $self->has_ignore_vars,
                    ignore_vars => \%ignore_vars,
                },
            ),
        })
    );
};

__PACKAGE__->meta->make_immutable;
no Moose;
1;

=head1 SYNOPSIS

In C<dist.ini>:

    [Test::UnusedVars]

Or, give a list of files to test:

    [Test::UnusedVars]
    file = lib/My/Module.pm
    file = bin/verify-this

Ignore some variables:

    [Test::UnusedVars]
    ignore_var = $guard
    ignore_var = $raii

Ignore variables in a particular file:

    [Test::UnusedVars]
    ; ignore $guard in all files
    ignore_var = $guard
    ; ignore $foo only in lib/My/Module.pm
    ignore_var = lib/My/Module.pm:$foo

    ; unfortunately, must list all files
    file = lib/My/Module.pm
    file = bin/verify-this

A file specific variable is only ignored if the file is specified in a C<file> option.
Unfortunately, because of the current implementation, this means that I<all> files must
be specified via C<file> options.


=for test_synopsis
1;
__END__

=head1 DESCRIPTION

This is an extension of L<Dist::Zilla::Plugin::InlineFiles>, providing the
following file:

    xt/release/unused-vars.t - a standard Test::Vars test

=cut

__DATA__
___[ xt/release/unused-vars.t ]___
#!perl

use Test::More 0.96 tests => 1;
eval { require Test::Vars };

SKIP: {
    skip 1 => 'Test::Vars required for testing for unused vars'
        if $@;
    Test::Vars->import;

    subtest 'unused vars' => sub {
{{
    my $qwote_vars = sub { join ' ', 'qw[', @{ $ignore_vars{$_[0]} }, ']' };
    my $indent = "    " x 2;

    if ( $has_files ) {
        for my $file ( @files ) {
            $OUT .= "\n" if length $OUT;
            $OUT .= $indent;
            (my $qfile = $file ) =~ s{'}{\\'}g;;
            if ( $ignore_vars{$file} ) {
                $OUT .= "vars_ok('$qfile', ignore_vars => [ @{[ $qwote_vars->($file) ]} ] );";
            }
            else {
                $OUT .= "vars_ok('$qfile');"
            }
        }
    }

    else {
        $OUT .= $indent;
        if ( $has_ignore_vars && defined $ignore_vars{''} ) {
            $OUT .= "all_vars_ok( ignore_vars => [ @{[ $qwote_vars->('') ]} ] );"
        }
        else {
            $OUT .= "all_vars_ok();"
        }
    }
}}
    };
};
