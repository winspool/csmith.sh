# csmith.sh

 Welcome to a nice script with TAP output to generate testfiles with csmith </br>
 and compare the results of a testing c/c++ compiler ( $TESTCC | $TESTCXX ) </br>
 with the results of a reference c/c++ compiler ( $REFCC | $REFCXX ) </br>

 On failure, additional helper scripts for 'creduce' are created.


## Usage: 
```
 csmith.sh [first_seed] [-] [last_seed]
```

 csmith is called with a seed value to create reproducible testfiles </br>
 default range for the seed value is 0 - 1000 </br>
 (use command line args for other ranges) </br>
 (a single value test the compilers with only one specific testfile)


## Supported environment variable

 * DEBUG          print many extra informations
 * CSMITH_BIN     use a different csmith binary
 * CSMITH_OPTIONS use additional options for csmith
 * RUNTIME_DIR    use this directory as working directory [ \$XDG_RUNTIME_DIR/$subdir | /tmp/$subdir ]

 * CSMITH_INCLUDE csmith include path for the compiler [ $CSMITH_INCLUDE ]

 * REFCC          c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
 * REFCXX         c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
 * REFCCFLAGS     extra flags for the c reference compiler
 * REFCXXFLAGS    extra flags for the c++ reference compiler

 * TESTCC         c compiler to test    [ \$CC ]
 * TESTCXX        c++ compiler to test  [ \$CXX ]
 * TESTCCFLAGS    extra flags for the c compiler to test  [ \$CCFLAGS ]
 * TESTCXXFLAGS   extra flags for the c++ compiler to test  [ \$CXXFLAGS ]


## Define the reference compiler and related flags in the scriptname

 The scriptname can be used to define a reference compiler and related flags. </br>
 After the ".sh" extension was stripped, the remaining dots are used to split additional options </br>

 Examples:
 * csmith.tcc.sh
 * csmith.gcc.-m32.sh
 * csmith.clang.--target.x86_64-linux-musl.sh

## More details

 Testfiles are created in a subdirectory of XDG_RUNTIME_DIR (which is normally a RAM-Disc, based on tmpfs). </br>
 This is much faster and avoids write pressure on a physical disc (probably a flask disc).

 When building or running a test binary or comparing the result fails, </br>
 additional shell scripts are created, which can be used for "creduce" as "interestingness_test"

 To avoid to fill up the disk, all files for the current seed value are deleted, </br>
 when both compile variants work and running the created programs produced the same result.

 The output of this script is compatible to TAP: Test Anything Protocol
 
 LICENSE: MIT


