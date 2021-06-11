#!/bin/bash

## TO USER
##
## Usage: sjson.sh <path/for/config>
##        Transfer file in specify format to json.
## Note: It not support all features of JSON even though space.
## Format: <path/for/json/node>:<type>:<value>
##
## Eg. <test.conf as the following>
##     /a/b/c/d0:int:2
##     /a/b/c/d1:string:hello
##     /a/b/c0/d:bool:true
##     /a/b0/c/d:array:str1,str2,str3
##
##     <the following json you get>
##     $ sjson.sh test.conf
##     {
##         "a" : {
##             "b" : {
##                 "c" : {
##                     "d0" : 2,
##                     "d1" : "hello"
##                 },
##                 "c0" : {
##                     "d" : false
##                 }
##             },
##             "b0" : {
##                 "c" : {
##                     "d" : [ "str1", "str2", "str3" ]
##                 }
##             }
##         }
##     }

# get_next <key_path:...>
## Node: get words following '@' but before ':' or '/'
##       '@' means recursive call working at
## in: /path/for@json/node:bool:value
## out: json
get_next()
{
    echo $1 | sed 's#.*@\([^/:]*\).*#\1#'
}

# get_pre <key_path:...>
## Node: get words before '@'
##       '@' means recursive call working at
## in: /path/for@json/node:bool:value
## out: for
get_pre()
{
    echo $1 | sed 's#.*/\([^/:]*\)@.*#\1#'
}

# is_end <key_path:...>
## Note: check whether the last node
##       '@' means recursive call working at
## eg. /path/for@json/node:bool:value => false (Not 0)
##     /path/for/json@node:bool:value => ture (0)
is_end()
{
    echo $1 | grep -q "@[^/]*:"
}

# move_next <key_path:...>
# Note: move '@' to next '/'
#       '@' means recursive call working at
# in: /path@for/json/node:bool:value
# out: /path/for@json/node:bool:value
move_next()
{
    is_end $1 && return 1
    echo $1 | sed 's#\(.*\)@\([^/]*\)/\(.*\)#\1/\2@\3#'
}


# get_type <key_path:key_type:key_value>
## in: /path/for/json/node:bool:value
## out: bool
get_type()
{
    local tmp=${1%:*}
    echo ${tmp##*:}
}

# get_path <key_path:key_type:key_value>
## in: /path/for/json/node:bool:value
## out: /path/for/json/node
get_path()
{
    echo ${1%%:*}
}

# get_value <key_path:key_type:key_value>
## in: /path/for/json/node:bool:value
## out: value
get_value()
{
    echo ${1##*:}
}

# draw_indent <depth>
draw_indent() {
    local cnt
    for cnt in `seq 1 $1`
    do
        echo -n "    "
    done
}

# draw_item <flag> <depth> <key1_path:key2_type:key2_value> ...
## flag: whether draw comma
##       c: there are items in clist, so draw comma
##       e: there are no items in clist, so don't draw comma
draw_item()
{
    local flag=$1 && shift
    local depth=$1 && shift

    local branch type cnt val conf
    for branch in $@
    do
        cnt=$(( ${cnt} + 1 ))
        val=$(get_value ${branch})
        node=$(get_next ${branch})
        typ=$(get_type ${branch})

        draw_indent ${depth} && echo -n "\"${node}\" : "
        case "${typ}" in
            "bool")
                [ "${val}" = "y" ] && echo -n "true" || echo -n "false"
                ;;
            "int")
                echo -n "${val}"
                ;;
            "array")
                echo -n "[ "
                echo ${val} | awk -F, '{
                     for (i = 1; i <= NF; i++) {
                         printf "\"%s\"", $i
                         if (i != NF)
                             printf ", "
                     }
                 }'
                echo -n " ]"
                ;;
            "string")
                echo -n "\"$(echo ${val} | sed 's#"#\\"#g')\""
                ;;
            "*")
                echo "invalid type ${branch}" && exit 1
        esac
        [ "${cnt}" -ge "$#" -a "${flag}" = "e" ] && echo || echo ","
    done
}

sjson_create_do() {
    local depth=$1 && shift

    # classify
    local trunks trunks_cnt trunk branch
    for branch in $@
    do
        trunk=$(get_next ${branch})
        ! (echo ${trunks} | grep -qw "${trunk}") \
            && trunks="${trunks} ${trunk}" && trunks_cnt=$(( trunks_cnt + 1 ))
        trunk="$(echo ${trunk} | sed 's/[^ [:alnum:]]/_/g')"
        eval "local ${trunk}=\"\${${trunk}} ${branch}\""
    done

    # draw json
    local elist clist cnt next
    for trunk in ${trunks}
    do
        draw_indent ${depth} && echo "\"${trunk}\" : {"

        trunk="$(echo ${trunk} | sed 's/[^ [:alnum:]]/_/g')"
        for branch in $(eval "echo \${${trunk}}")
        do
            next="$(move_next ${branch})"
            if is_end ${next}; then
                elist="${elist} ${next}"
            else
                clist="${clist} ${next}"
            fi
        done
        [ -n "${elist}" ] && draw_item \
            $([ -n "${clist}" ] && echo c || echo e) \
            $(( ${depth} + 1 )) ${elist}
        [ -n "${clist}" ] && sjson_create_do $(( ${depth} + 1 )) ${clist}

        cnt=$(( ${cnt} + 1 ))
        if [ "${cnt}" -lt "${trunks_cnt}" ]; then
            draw_indent ${depth} && echo "},"
        else
            draw_indent ${depth} && echo "}"
        fi
        unset clist elist
    done
}

# sjson_create <path/for/file>
sjson_create() {
    [ ! -f "$1" ] && echo not found $1 && exit 1

    local item
    for item in `cat $1`
    do
        if ! $(echo ${item} | grep -q '^/'); then
            echo "must start with '/': ${item}" && exit 1
        fi
        cxt="${cxt} `echo ${item} | sed 's#^/#@#'`"
    done

    echo '{' && sjson_create_do 1 $cxt && echo '}'
}

sjson_create $@
