all:
	(rebar get-deps compile generate)

clean:
	(rebar clean)

distclean:
	(rebar clean delete-deps)

# dialyzer --build_plt --apps erts kernel stdlib crypto mnesia sasl eunit xmerl -r ./deps/*/ebin ./deps/*/include
check:
	(dialyzer -I ./include/ -c ./src/*.erl)
