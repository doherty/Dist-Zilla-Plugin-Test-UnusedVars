use strict;
use warnings;
use Test::More 0.96 tests => 3;
use autodie;
use Test::DZil;
use List::Util qw( first );
use Path::Tiny;
use File::pushd;

my $has_IPC_RUN3 = eval "use IPC::Run3; 1;";

# all of the unused variables that are in the files.
use constant VARS => qw( $var1 @var2 %var3 );

# files, both as we (this file) see them and as is in the normalized form in the test code
use constant FILES     => qw( lib/DZ1/file1.pm lib/DZ1/file2.pm );
use constant normFILES => qw(     DZ1/file1.pm     DZ1/file2.pm );

# a subset of the unused variables that will be ignored
use constant IgnoredFileVARS =>
  qw( lib/DZ1/file1.pm:$var1
      lib/DZ1/file2.pm:@var2
      lib/DZ1/file2.pm:%var3
);

# all of the unused variables if there are no ignores, in "$file:$var" form
use constant NoIgnores => sort
                    map {
                        my $var = $_;
                        map {
                            "$_:$var"
                        } FILES
                    } VARS;

sub gen_code {

    my $tzil = Builder->from_config(
        { dist_root => 'corpus/DZ1' },
        {
            add_files => {
                'source/dist.ini' =>
                  simple_ini( 'GatherDir', ['Test::UnusedVars', { @_ } ], ),
            },
        } );

    my $guard = pushd 'corpus/DZ1';
    $tzil->build;

    my ( $test ) = first { $_->name eq 'xt/release/unused-vars.t' } @{ $tzil->files };

    return $test->content;
}

sub run_code {
    my  ($code, $stdout, $stderr) = @_;
    my $guard = pushd 'corpus/DZ1';
    run3( [$^X => '-Ilib' ], $code, $stdout, $stderr );
}

# extract the "used once" errors from a test run so that we can test for completeness.
sub grep_output {
    my $output = shift;

    [ sort map {
        m{(\S+)\s* is used once .* at (lib/.*\.pm)};
        "$2:$1"
            } grep { /is used once/ } split(/\n/, $output )
   ]
}

sub subtestx { }

# make sure the tests actually work
subtest 'base' => sub {

    subtest 'all files' => sub {

        plan skip_all => "requires IPC::Run3 to test"
          unless $has_IPC_RUN3;

        my $code = gen_code();

        run_code( \$code, \my $stdout, \my $stderr );
        isnt( $?, 0, "run test on code" )
          or diag "expected errors, got none?";

        is_deeply( grep_output( $stderr ), [ NoIgnores ], "unused vars" );
    };

    subtest 'files' => sub {

        plan skip_all => "requires IPC::Run3 to test"
          unless $has_IPC_RUN3;

        plan tests => 2;

        my $code = gen_code( files => [ FILES ] );

        run_code( \$code, \my $stdout, \my $stderr );
        isnt( $?, 0, "run test on code" )
          or diag "expected errors, got none?";

        is_deeply( grep_output( $stderr ), [ NoIgnores ] , "unused vars" );
    };
};

subtest 'global ignore vars' => sub {
    plan tests => 2;

    subtest 'all files' => sub {
        plan tests => 2;

        my @vars = VARS;
        my $code = gen_code( ignore_vars => \@vars );

        subtest "generated test" => sub {
            plan tests => 2 + @vars;

            unlike $code => qr{\svars_ok}, "shouldn't have individual file tests";
            like   $code => qr{all_vars_ok}, "should have all file tests";
            like   $code => qr{\Q$_}, "ignore $_" for @vars;
        };

        subtest "run test" => sub {
            plan skip_all => "requires IPC::Run3 to test", 1
              unless $has_IPC_RUN3;

            plan tests => 1;

            run_code( \$code, \my $stdout, \my $stderr );
            is( $?, 0, "run test on code" )
              or do {
                diag "Test Code:\n", $code;
                diag "STDERR:\n$stderr";
                diag "STDOUT:\n$stdout";
              };
        };
    };


    subtest 'files' => sub {
        plan tests => 2;

        my @vars  = VARS;
        my @files = FILES;
        my @norm_files = normFILES;

        my $code = gen_code( files => \@files, ignore_vars => \@vars );

        subtest "generated test" => sub {
            plan tests => 1 + @vars * @files;

            unlike $code => qr{all_vars_ok}, "shouldn't have all file tests";

            for my $file ( @norm_files ) {
                like $code => qr{\svars_ok.*'$file'\s?,.*\Q$_}, "$file, $_"
                  for @vars;
            }
        };

        subtest "run test" => sub {
            plan skip_all => "requires IPC::Run3 to test", 1
              unless $has_IPC_RUN3;

            plan tests => 1;

            run_code( \$code, \my $stdout, \my $stderr );
            is( $?, 0, "run test on code" )
              or do {
                diag "Test Code:\n", $code;
                diag "STDERR:\n$stderr";
                diag "STDOUT:\n$stdout";
              };
        };
    };
};


subtest 'per-file ignore vars' => sub {
    plan tests => 2;

    subtest 'all files' => sub {
        plan tests => 2;

        my @vars = VARS;
        my $code = gen_code( ignore_vars => [IgnoredFileVARS] );

        subtest "generated test" => sub {
            plan tests => 2 + @vars;

            unlike $code => qr{\svars_ok}, "shouldn't have individual file tests";
            like $code => qr{all_vars_ok}, "should have all file tests";
            unlike $code => qr{\Q$_}, "shouldn't ignore $_" for @vars;
        };

        subtest "run test" => sub {
            plan skip_all => "requires IPC::Run3 to test", 1
              unless $has_IPC_RUN3;

            plan tests => 1 + @vars;

            run_code( \$code, \my $stdout, \my $stderr );
            isnt( $?, 0, "run test on code" )
              or diag "expected errors, got none?";

             note $stderr;

            like $stderr, qr{\Q$_ is used once}, "$_ is used once" for @vars;
        };
    };

    subtest 'files' => sub {
        plan tests => 2;

        my @vars  = VARS;
        my @files = FILES;
        my $code = gen_code( files => \@files, ignore_vars => [ IgnoredFileVARS ] );

        subtest "generated test" => sub {
            plan tests => 3;

            unlike $code => qr{all_vars_ok}, "shouldn't have all file tests";
            like   $code => qr{\svars_ok.*'DZ1/file1\.pm'\s?,.*\$var1}, 'file1, $var1';
            like   $code => qr{\svars_ok.*'DZ1/file2\.pm'\s?,.*\@var2\s+%var3}, 'file2, @var2, %var3';
        };

        subtest "run test" => sub {
            plan skip_all => "requires IPC::Run3 to test", 1
              unless $has_IPC_RUN3;

            plan tests => 2;

            run_code( \$code, \my $stdout, \my $stderr );
            isnt( $?, 0, "run test on code" )
              or do {
                diag "Test Code:\n", $code;
                diag "STDERR:\n$stderr";
                diag "STDOUT:\n$stdout";
              };

            is_deeply( grep_output( $stderr ),
                       [
                        sort
                        qw( lib/DZ1/file2.pm:$var1
                            lib/DZ1/file1.pm:@var2
                            lib/DZ1/file1.pm:%var3
                         )
                       ],
                       "unused vars" );
        };
    };
};
