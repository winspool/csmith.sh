#!/bin/sh
## Copyright (c) 2022-2023, Detlef Riekenberg
## SPDX-License-Identifier: MIT
##
## a script with TAP output to generate testfiles with csmith
## and compare the results of a testing c/c++ compiler ( $TESTCC | $TESTCXX )
## with the results of a reference c/c++ compiler ( $REFCC | $REFCXX )
##
## usage: $appname [first_seed] [-] [last_seed]
##
## csmith is called with a seed value to create reproducible testfiles
## default range for the seed value: 0 - 1000
##  - (use command line args for other ranges)
##  - (a single value generates only one specific test)
##
## supported environment variables:
## DEBUG          print many extra informations
## CSMITH_BIN     a different csmith binary [ $CSMITH_BIN ]
## CSMITH_OPTIONS additional options for csmith
## RUNTIME_DIR    working directory     [ \$XDG_RUNTIME_DIR/$subdir | /tmp/$subdir ]
##
## CSMITH_INCLUDE csmith include path for the compiler [ $CSMITH_INCLUDE ]
##
## REFCC          c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
## REFCXX         c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
## REFCCFLAGS     extra flags for the c reference compiler
## REFCXXFLAGS    extra flags for the c++ reference compiler
##
## TESTCC         c compiler to test    [ \$CC ]
## TESTCXX        c++ compiler to test  [ \$CXX ]
## TESTCCFLAGS    extra flags for the c compiler to test  [ \$CCFLAGS ]
## TESTCXXFLAGS   extra flags for the c++ compiler to test  [ \$CXXFLAGS ]
##
## The scriptname can be used to define the std mode, a reference compiler and related flags
## In the first part (upto the first dot), the underscore can be used to select the std.
## After the ".sh" extension was stripped, more dots are used to split additional options
## Examples: csmith.tcc.sh or csmith_c11.gcc.-strict.sh
##
## Testfiles are created in a subdirectory of XDG_RUNTIME_DIR
## (which is normally a RAM-Disc, based on tmpfs).
## This is much faster and avoids write pressure on a physical disc (probably a flask disc). 
##
## When building or running a test binary or comparing the result fails, 
## additional shell scripts are created, 
## which can be used for "creduce" as "interestingness_test"
##
## To avoid to fill up the disk, all files for the current seed value are deleted,
## when both compile variants work and running the created programs produced the same result.
##
## The output of this script is compatible to TAP: Test Anything Protocol
##
##


fullname="`basename "$0" `"
appname="`basename "$0" ".sh"`"
shortname="`echo "$appname" | cut -d "." -f1`"

old_pwd="`pwd`"
my_pid="`echo $$`"

utc_year="`date -u +%Y`"
utc_month="`date -u +%m`"
utc_day="`date -u +%d`"
utc_dayofyear="`date -u +%j`"

debug_me="$DEBUG"

#subdir="$appname_$utc_dayofyear"
#subdir="$appname$my_pid"
#subdir="$appname"
subdir="$shortname"


# range for the csmith seed value
id_first="0"
id_last="1000"


# "c99" for "-std=c99", "c11" for -std="c11"
# "c++03" for "-std=c++03", "c++11" for "-std=c++11"
def_stdc="c99"
def_cplusplus="c++03"
def_std="$def_stdc"

#file extension for c++ files
cxxext=".cpp"


if [ -z "$CSMITH_BIN" ]
then
    CSMITH_BIN="csmith"
fi

if [ -z "$CSMITH_INCLUDE" ]
then
    CSMITH_INCLUDE="/usr/include/csmith"
fi

##
# default options for running the compiler:
# disable all optimizations
def_opt="-O0"
# enable debug infos
def_debug="-g"
# link with the math library 
def_libm="-lm"
#disable all warnings
def_warn="-w "
# owcc needs "-Wlevel=0 " to disable warnings
#def_warn="-Wlevel=0 "
# zig cc enables ub-sanitizer by default
#def_warn="-w -fno-sanitize=undefined"
##

def_refcc="gcc"
def_refcxx="g++"

# timeout for running the compiled programm
def_timeout="8"


# all configuration options are above #
#######################################

csmith_set_std=""
compiler_set_std=""

## use c or c++ for c_or_cxx
c_or_cxx=""
std_version=""

# count success / failures
test_id=0
n_fails=0
n_ok=0

## try to detect a reference toolchain from the scriptname
toolchain="`echo "$appname" | cut -d "." -f2`"
toolflags="`echo "$appname" | cut -d "." -f3- | tr "." " " `"

if [ "$toolchain" = "$shortname" ]
then
    toolchain=""
    toolflags=""
fi

if [ -n "$debug_me" ]
then
echo "# appname:     $appname"
echo "# shortname:   $shortname"
echo "# toolchain:   $toolchain"
echo "# toolflags:   $toolflags"
echo "# with csmith: $CSMITH_BIN"
fi


# try to detect the standard to use from the scriptname
try_as_std="`echo "$shortname" | cut -d "_" -f2`"
if [ "$try_as_std" = "$shortname" ]
then
    try_as_std=""
else
    c_or_cxx="`echo "$try_as_std" | tr -d "0123456789"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi


## try to detect our language mode from the environment: c or c++
if [ -z "$c_or_cxx" ]
then
    if [ -n "$REFCC" ] 
    then
        c_or_cxx="c"
        REFCXX=""
        REFCXXFLAGS=""
    fi
    if [ -n "$REFCXX" ] 
    then
        c_or_cxx="c++"
        REFCC=""
        REFCCFLAGS=""
    fi

    if [ -n "$TESTCC" ] 
    then
        c_or_cxx="c"
        TESTCXX=""
        TESTCXXFLAGS=""
    fi

    if [ -n "$TESTCXX" ] 
    then
        c_or_cxx="c++"
        TESTCC=""
        TESTCCFLAGS=""
    fi
fi

if [ -z "$c_or_cxx" ]
then
    if [ -n "$CC" ] 
    then
        c_or_cxx="c"
    fi
fi

if [ -z "$c_or_cxx" ]
then
    if [ -n "$CXX" ] 
    then
    c_or_cxx="c++"
    fi
fi

if [ -z "$c_or_cxx" ]
then
    try_as_std="$def_std"
    c_or_cxx="`echo "$try_as_std" | tr -d "[0-9]"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi

###
# when we do not have a std version, use out default
if [ -z "$std_version" ]
then
    if [ "$c_or_cxx" = "c" ]
    then
        try_as_std="$def_stdc"
    else
        try_as_std="$def_cplusplus"
    fi
    c_or_cxx="`echo "$try_as_std" | tr -d "0123456789"`"
    std_version="`echo "$try_as_std" | tr -d "+[a-z]"`"
fi


###
if [ -n "$debug_me" ]
then
    echo "# using std:   $c_or_cxx$std_version"
fi


## We have now a language mode: c or c++ (anything else) and a version

if [ "$c_or_cxx" = "c" ]
then
    srcext=".c"
    csmith_set_std=""
    compiler_set_std="-std=$c_or_cxx$std_version"
else
    srcext="$cxxext"
    compiler_set_std="-std=$c_or_cxx$std_version"
    case "$std_version" in
    "98" | "03" )
        csmith_set_std="--lang-cpp"
        ;;
    "11" )
        csmith_set_std="--lang-cpp --cpp11"
        ;;
    *)
        echo "c++ version not supported: $std_version"
        exit 1
    esac
fi

COMPILER_FLAGS=" $compiler_set_std  $def_opt $def_debug $def_libm $def_warn  -I$CSMITH_INCLUDE "

# cleanup working directory (default: no cleanup)
cleanup_dir=""


if [ -z "$RUNTIME_DIR" ]
then
    if [ -n "$XDG_RUNTIME_DIR" ]
    then
        RUNTIME_DIR="$XDG_RUNTIME_DIR/$subdir"
    else
        RUNTIME_DIR="/tmp/$subdir"
    fi
    # cleanup our working directory, when everything succeeds
    cleanup_dir="$RUNTIME_DIR"
fi

if [ "$c_or_cxx" = "c" ]
then
    REFCXX=""
    HOSTCXX=""
    BUILDCXX=""
    TESTCXX=""
    CXX=""
    REFCXXFLAGS=""
    HOSTCXXFLAGS=""
    BUILDCXXFLAGS=""
    TESTCXXFLAGS=""
    CXXFLAGS=""

    if [ -z "$REFCC" ]
    then
        if [ -n "$HOSTCC" ] 
        then
            REFCC="$HOSTCC"
            REFCCFLAGS="$HOSTCCFLAGS"
        elif [ -n "$BUILDCC" ] 
        then
            REFCC="$BUILDCC"
            REFCCFLAGS="$BUILDCCFLAGS"
        fi
    fi

    if [ -z "$REFCC" ]
    then
        REFCC="$toolchain"
    fi
    if [ -z "$REFCC" ]
    then
        REFCC="$def_refcc"
    fi

    if [ -z "$REFCCFLAGS" ]
    then
        REFCCFLAGS="$toolflags"
    fi


    if [ -z "$TESTCC" ]
    then
        TESTCC="$CC"
    fi
    if [ -z "$TESTCCFLAGS" ]
    then
        TESTCCFLAGS="$CFLAGS"
    fi


else

    REFCC=""
    HOSTCC=""
    BUILDCC=""
    TESTCC=""
    CC=""
    REFCCFLAGS=""
    HOSTCCFLAGS=""
    BUILDCCFLAGS=""
    TESTCCFLAGS=""
    CFLAGS=""

    if [ -z "$REFCXX" ]
    then
        if [ -n "$HOSTCXX" ] 
        then
            REFCXX="$HOSTCXX"
            REFCXXFLAGS="$HOSTCXXFLAGS"
        elif [ -n "$BUILDCXX" ] 
        then
            REFCXX="$BUILDCXX"
            REFCXXFLAGS="$BUILDCXXFLAGS"
        fi
    fi

    if [ -z "$REFCXX" ]
    then
        REFCXX="$toolchain"
    fi
    if [ -z "$REFCXX" ]
    then
        REFCXX="$def_refcxx"
    fi

    if [ -z "$REFCXXFLAGS" ]
    then
        REFCXXFLAGS="$toolflags"
    fi


    if [ -z "$TESTCXX" ]
    then
        TESTCXX="$CXX"
    fi
    if [ -z "$TESTCXXFLAGS" ]
    then
        TESTCXXFLAGS="$CXXFLAGS"
    fi

fi


# A test compiler is always needed
if [ -z "$TESTCC$TESTCXX" ]
then
    echo "No test compiler found"
    exit 1
fi

## parsing command line parameter starts here

n=0
n_last=0



if [ -n "$1" ]
then

    case "$1" in
    "-h" | "--help" | "/?" )
        cat <<EOF
usage: $fullname [first_seed] [-] [last_seed]

Generate testfiles with csmith and compare the results
of a testing c/c++ compiler ( $TESTCC$TESTCXX )
with a reference c/c++ compiler ( $REFCC$REFCXX )

csmith is called with a seed value to create reproducible testfiles
default range for the seed value: 0 - 1000
 - (use command line args for other ranges)
 - (a single value generates only one specific test)

supported environment variables:
CSMITH_BIN     a different csmith binary [ $CSMITH_BIN ]
CSMITH_OPTIONS additional options for running $CSMITH_BIN

RUNTIME_DIR    working directory     [ \$XDG_RUNTIME_DIR/$subdir | /tmp/$subdir ]

CSMITH_INCLUDE csmith include path for the compiler [ $CSMITH_INCLUDE ]

REFCC          c reference compiler  [ \$HOSTCC | \$BUILDCC | $def_refcc ]
REFCXX         c++ reference compiler[ \$HOSTCXX | \$BUILDCXX | $def_refcxx ]
REFCCFLAGS     extra flags for the c reference compiler [ $REFCFLAGS ]
REFCXXFLAGS    extra flags for the c++ reference compiler [ $REFCXXFLAGS ]

TESTCC         c compiler to test    [ \$CC ]
TESTCXX        c++ compiler to test  [ \$CXX ]
TESTCCFLAGS    extra flags for the c compiler to test [ \$CCFLAGS ]
TESTCXXFLAGS   extra flags for the c++ compiler to test [ \$CXXFLAGS ]

EOF
        exit 1
        ;;
        
    * ) 
        ;;
    esac

    n_first="`echo "$1" | cut -d "-" -f1 `"
    n_last="`echo "$1" | cut -d "-" -f2 `"

    if [ "$1" = "$n_first" ]
    then

        id_first="$n_first"
        if [ -n "$2" ]
        then
            shift
        fi
    else
        if [ -n "$n_first" ]
        then
            id_first="$n_first"
        fi
        if [ -n "$n_last" ]
        then
            id_last="$n_last"
        fi
        shift
    fi

    if [ "$1" = "-" ]
    then
        shift
    fi

    if [ -n "$1" ]
    then
        id_last="$1"
    fi

fi


n=$(($id_first))
n_last=$(($id_last))

if [  $n -lt 0 ]
then
    n=0;
    n_last=$(($id_first * -1))
else
    if [  $n_last -lt 0 ]
    then
        n_last=$(($id_last * -1))
    fi
fi

if [  $n -gt $n_last ]
then
    tmp=$n
    n=$n_last
    n_last=$tmp
fi


echo "# using csmith binary:      $CSMITH_BIN"
if [ -n "$CSMITH_OPTIONS" ]
then
echo "# using csmith options:     $CSMITH_OPTIONS"
fi
echo "# using csmith seed range:  $n to $n_last" 
echo "# using working directory:  $RUNTIME_DIR"
echo "# using reference compiler: $REFCC$REFCXX"
echo "# using reference flags:    $REFCCFLAGS$REFCXXFLAGS"
echo "# using testing compiler:   $TESTCC$TESTCXX"
echo "# using testing flags:      $TESTCCFLAGS$TESTCXXFLAGS"
echo ""


mkdir -p "$RUNTIME_DIR"

while [ $n -le $n_last ]
do

    f=0
    this_id="`seq --format=%05.f ${n} ${n} `"
    this_file="$RUNTIME_DIR/$this_id"
    local_file="./$this_id"

    if [ ! -f "$this_file""$srcext" ]
    then
#        echo "# creating ""$this_file""$srcext"
        if [ -n "$debug_me" ]
        then
            echo "# "$CSMITH_BIN  --float $csmith_set_std $CSMITH_OPTIONS --seed $n --output "$this_file""$srcext"
        fi
        $CSMITH_BIN  --float $csmith_set_std $CSMITH_OPTIONS --seed $n --output "$this_file""$srcext"
    fi


    if [ -n "$debug_me" ]
    then
        echo "# REF  compile: "$REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$this_file""$srcext"   -o "$this_file""_ref"
    fi

    $REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$this_file""$srcext"   -o "$this_file""_ref"
    if [ $? -ne 0 ]
    then
        test_id=$(($test_id + 1))
        echo "not ok # compile REF: $this_file""$srcext"
        echo "       # " $REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$this_file""$srcext" -o "$this_file""_ref"
        n_fails=$((n_fails + 1))
        f=$(($f + 1))

        echo  >"$this_file""_ref_cc.sh" "#!/bin/sh"
        echo >>"$this_file""_ref_cc.sh" ""$REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$local_file""$srcext" -o "$local_file""_ref"
        chmod "a+x" "$this_file""_ref_cc.sh"
    fi


    if [ -n "$debug_me" ]
    then
        echo "# TEST compile: "$TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$this_file""$srcext" -o "$this_file""_tst"
    fi

    $TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$this_file""$srcext" -o "$this_file""_tst"
    if [ $? -ne 0 ]
    then
        test_id=$(($test_id + 1))
        echo "not ok # compile TEST: $this_file""$srcext"
        echo "       # "$TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$this_file""$srcext" -o "$this_file""_tst"
        n_fails=$((n_fails + 1))
        f=$(($f + 2))

        echo  >"$this_file""_tst_cc.sh" "#!/bin/sh"
        echo >>"$this_file""_tst_cc.sh" ""$TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$local_file""$srcext" -o "$local_file""_tst"
        chmod "a+x" "$this_file""_tst_cc.sh"
    fi


    if [ -n "$debug_me" ]
    then
        echo "# run: ""$this_file""_ref" ">""$this_file""_ref.txt" 
    fi

    timeout $def_timeout "$this_file""_ref" > "$this_file""_ref.txt"
    if [ $? -ne 0 ]
    then
        test_id=$(($test_id + 1))
        echo "not ok # run $this_file""_ref"
        n_fails=$((n_fails + 1))
        f=$(($f + 4))

        echo  >"$this_file""_ref_run.sh" "#!/bin/sh"
        echo >>"$this_file""_ref_run.sh" "# use: creduce $local_file""_ref_run.sh  $this_id""_reduced""$srcext"
        echo >>"$this_file""_ref_run.sh" ""

        echo >>"$this_file""_ref_run.sh" "if [ ! -f ""$local_file""_reduced""$srcext" "] ; then "
        echo >>"$this_file""_ref_run.sh" "#COPY cp "$local_file""$srcext" "$local_file""_reduced""$srcext" "
        echo >>"$this_file""_ref_run.sh" "" $REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$local_file""$srcext" -E -o "$local_file""_reduced""$srcext" 
        echo >>"$this_file""_ref_run.sh" "fi"
        echo >>"$this_file""_ref_run.sh" ""

        echo >>"$this_file""_ref_run.sh" ""$REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$local_file""_reduced""$srcext" -o "$local_file""_reduced""_ref"
        echo >>"$this_file""_ref_run.sh" "if [ $""? -ne 0 ] ; then exit 1"
        echo >>"$this_file""_ref_run.sh" "fi"
        echo >>"$this_file""_ref_run.sh" ""
        echo >>"$this_file""_ref_run.sh" ""timeout $def_timeout "$local_file""_reduced""_ref" ">""$local_file""_reduced""_ref.txt"
        echo >>"$this_file""_ref_run.sh" "if [ $""? -ne 0 ] ; then exit 0"
        echo >>"$this_file""_ref_run.sh" "fi"
        echo >>"$this_file""_ref_run.sh" "exit 1"
        chmod "a+x" "$this_file""_ref_run.sh"
    else
        if [ -n "$debug_me" ]
        then
            echo "# res: "`cat "$this_file""_ref.txt"`
        fi
    fi


    if [ -n "$debug_me" ]
    then
        echo "# run: ""$this_file""_tst" ">""$this_file""_tst.txt"
    fi

    timeout $def_timeout "$this_file""_tst" > "$this_file""_tst.txt"
    if [ $? -ne 0 ]
    then
        test_id=$(($test_id + 1))
        echo "not ok # run $this_file""_tst"
        n_fails=$((n_fails + 1))
        f=$(($f + 8))

        echo  >"$this_file""_tst_run.sh" "#!/bin/sh"
        echo >>"$this_file""_tst_run.sh" "# use: creduce [--timing] $local_file""_tst_run.sh  $this_id""_reduced""$srcext"
        echo >>"$this_file""_tst_run.sh" ""

        echo >>"$this_file""_tst_run.sh" "if [ ! -f $local_file""_reduced""$srcext ] ; then "
        echo >>"$this_file""_tst_run.sh" "#COPY cp "$local_file""$srcext" "$local_file""_reduced""$srcext" "
        echo >>"$this_file""_tst_run.sh" "#REF "$REFCC$REFCXX $COMPILER_FLAGS $REFCCFLAGS$REFCXXFLAGS "$local_file""$srcext" -E -o "$local_file""_reduced""$srcext"
        echo >>"$this_file""_tst_run.sh" ""$TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$local_file""$srcext" -E  -o "$local_file""_reduced""$srcext"
        echo >>"$this_file""_tst_run.sh" "fi"
        echo >>"$this_file""_tst_run.sh" ""

        echo >>"$this_file""_tst_run.sh" ""$TESTCC$TESTCXX $COMPILER_FLAGS $TESTCCFLAGS$TESTCXXFLAGS "$local_file""_reduced""$srcext" -o "$local_file""_reduced""_tst"
        echo >>"$this_file""_tst_run.sh" "if [ $""? -ne 0 ] ; then exit 1"
        echo >>"$this_file""_tst_run.sh" "fi"
        echo >>"$this_file""_tst_run.sh" ""

        echo >>"$this_file""_tst_run.sh" ""timeout $def_timeout "$local_file""_reduced""_tst" ">""$local_file""_reduced""_tst.txt"
        echo >>"$this_file""_tst_run.sh" "if [ $""? -ne 0 ] ; then exit 0"
        echo >>"$this_file""_tst_run.sh" "fi"
        echo >>"$this_file""_tst_run.sh" "exit 1"
        chmod "a+x" "$this_file""_tst_run.sh"
    else
        if [ -n "$debug_me" ]
        then
            echo "# res: "`cat "$this_file""_tst.txt"`
        fi
    fi



    diff_result=` diff -u  "$this_file""_ref.txt" "$this_file""_tst.txt" ` 
    if [ $? -ne 0 ]
    then
        test_id=$(($test_id + 1))
        echo "not ok # diff -u ""$this_file""_ref.txt  $this_file""_tst.txt"
        n_fails=$((n_fails + 1))
        f=$(($f + 16))

    fi

    if [ $f -eq 0 ]
    then
        test_id=$(($test_id + 1))
        echo "ok     #     $this_file""$srcext"
        n_ok=$((n_ok + 1))

        rm "$this_file""$srcext"
        rm "$this_file""_ref"
        rm "$this_file""_ref.txt"
        rm "$this_file""_tst"
        rm "$this_file""_tst.txt"
    else
        cleanup_dir=""
    fi
    n=$((n + 1))

    if [ -n "$debug_me" ]
    then
        echo ""
    fi

done


if [ -n "$cleanup_dir" ]
then
    rm 2>/dev/null -d "$cleanup_dir"
fi

# print a summary
if [ $n_ok -ne 1 ]
then
    echo "# $n_ok tests succeeded"
else
    echo "# 1 test succeeded"
fi

if [ $n_fails -ne 1 ]
then
    echo "# $n_fails tests failed"
else
    echo "# 1 test failed"
fi


if [ $n_fails -eq 0 ]
then
    echo "# All OK"
fi

echo "1..$test_id"

#########################

