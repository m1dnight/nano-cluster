%%
%% Vendored from atomvm_lib (include/trace.hrl @ master), unchanged. With
%% TRACE_ENABLED undefined - as it is here - ?TRACE expands to `ok`, so the
%% trace call sites (and the variables they would reference) compile away.
%%

-ifdef(TRACE_ENABLED).
-define(TRACE(Format, Args), io:format("~p ~p [~p:~p/~p:~p] " ++  Format ++ "~n", [erlang:system_time(millisecond), self(), ?MODULE, ?FUNCTION_NAME, ?FUNCTION_ARITY, ?LINE | Args])).
-else.
-define(TRACE(Format, Args), ok).
-endif.
