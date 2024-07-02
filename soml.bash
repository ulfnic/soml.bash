#!/usr/bin/env bash


soml__print_stderr() {
	if [[ $1 == '0' ]]; then
		[[ $2 ]] && printf "$2" "${@:3}" 1>&2 || :
	else
		[[ $2 ]] && printf '%s'"$2" "ERROR: ${0##*/}, line: ${line_num} " "${@:3}" 1>&2 || :
		return "$1"
	fi
}



if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2 ) )); then
	printf '%s\n' "ERROR: ${0##*/}, BASH version required >= 4.2 (released 2011)" 1>&2
	exit 1
fi



soml__read() {
	local \
		param_handler__exec=$1 \
		line_num=0 \
		external_IFS=$IFS \
		IFS parent_noglob_set line line_num heredoc_open line_prefix quoted val

	local -a soml__params


	shopt -q -o noglob && parent_noglob_set=1


	# Validate params
	[[ $param_handler__exec ]] && ! type "$param_handler__exec" &> /dev/null && soml__print_stderr 1 '%s\n' "param handler executable not found"
	[[ $SOML__PARAM_HANDLER_FUNC ]] && ! declare -F "$SOML__PARAM_HANDLER_FUNC" > /dev/null && soml__print_stderr 1 '%s\n' "SOML__PARAM_HANDLER_FUNC must contain the name of a function"


	while IFS= read -r line; do
		(( ++line_num ))

		line=${line#"${line%%[![:space:]]*}"} # Remove leading IFS
		line=${line//\\\\/\\134} # Convert escaped backslashs to octal


		# Construct $line
		if [[ $heredoc_open ]]; then
			if [[ $line != '"""'* ]]; then
				line=${line//\\'"'/\\042} # Convert escaped double-quotes
				line=${line//'"'/\\042} # Convert double-quotes

				if [[ $line == *'\' ]]; then
					line_prefix+=${line:0:-1}
					continue
				fi

				line_prefix+=$line'\n'
				continue
			fi

			heredoc_open=
			if [[ $line == *'\' ]]; then
				line_prefix+='"'${line:3}
				continue
			fi

			line=$line_prefix'"'${line:3}

		else
			if [[ $line == '#'* || ! $line ]]; then
				[[ $line_prefix ]] || continue
				line=$line_prefix

			else
				if [[ $line == *'\' ]]; then
					line_prefix+=${line:0:-1}
					continue
				fi

				if [[ $line == *'"""' ]]; then
					heredoc_open=1
					line_prefix+=${line:0:-2}
					continue
				fi

				[[ $line_prefix ]] && line=$line_prefix$line
			fi
		fi


		# $line is fully constructed
		line_prefix=


		# Prevent glob * pathname expansion so $line can be word split safely
		[[ $parent_noglob_set ]] || set -f


		# Divide $line into a paramater array using double-quotes to identify what's encapsulated
		line=${line//\\'"'/\\042} # Convert escaped double-quotes to octal
		line+='"' # Append a dq to prevent array split from squashing detectability of an EOL dq
		IFS='"'
		soml__params=($line)


		# Write the paramater array back into $line escaping tabs and spaces every other index
		line=
		quoted=1
		for val in "${soml__params[@]}"; do

			if [[ $quoted ]]; then
				quoted=
				line+=$val
				continue
			fi

			quoted=1
			if [[ $val ]]; then
				val=${val// /\\040} # Convert spaces to octal
				val=${val//	/\\011} # Convert tabs to octal
			else
				val='\0'
			fi
			line+=$val

		done

		[[ $quoted ]] && soml__print_stderr 1 '%s\n' "bad syntax, unterminating double-quotes"


		# Divide $line into a paramater array using tabs and spaces
		line=${line//\\ /\\040} # Convert escaped spaces to octal
		line=${line//\\	/\\011} # Convert escaped tabs to octal
		line=${line//\\%/\\045} # Convert escaped percents to octal
		line=${line//%/\\045} # Convert single percents to octal
		IFS=' 	' soml__params=($line)


		# Unescape each index of the paramater array
		for i in "${!soml__params[@]}"; do
			soml__params[i]=${soml__params[i]//'\\0'/''}
			printf -v soml__params[i] -- "${soml__params[i]}"
		done


		# Return pathname expansion to the parent setting
		[[ $parent_noglob_set ]] || set +f


		# Export formated params
		if [[ $param_handler__exec ]]; then
			"$param_handler__exec" "${soml__params[@]}" || return $?
			continue
		fi

		if [[ $SOML__PARAM_HANDLER_FUNC ]]; then
			IFS=$external_IFS
			"$SOML__PARAM_HANDLER_FUNC" || return $?
			external_IFS=$IFS
			continue
		fi

		printf ' %q' "${soml__params[@]}"
		printf '\n'

	done

	[[ $heredoc_open ]] && soml__print_stderr 1 '%s\n' 'bad syntax, unterminating heredoc'
	return 0
}



[[ -t 0 ]] || soml__read "$@" || exit $?



