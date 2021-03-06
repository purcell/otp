%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2012-2013. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.2
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%
-module(ssl_certificate_verify_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("public_key/include/public_key.hrl").

-include("ssl_internal.hrl").
-include("ssl_alert.hrl").
-include("ssl_internal.hrl").
-include("ssl_record.hrl").
-include("ssl_handshake.hrl").

-define(LONG_TIMEOUT, 600000).

%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------

suite() -> [{ct_hooks,[ts_install_cth]}].

all() ->
    [{group, active},
     {group, passive},
     {group, active_once},
     {group, error_handling}].


groups() ->
    [{active, [], tests()},
     {active_once, [], tests()},
     {passive, [], tests()},
     {error_handling, [],error_handling_tests()}].

tests() ->
    [server_verify_peer,
     server_verify_none,
     server_require_peer_cert_ok,
     server_require_peer_cert_fail,
     verify_fun_always_run_client,
     verify_fun_always_run_server,
     cert_expired,
     invalid_signature_client,
     invalid_signature_server,
     extended_key_usage_verify_peer,
     extended_key_usage_verify_none].

error_handling_tests()->
    [client_with_cert_cipher_suites_handshake,
     server_verify_no_cacerts,
     unknown_server_ca_fail,
     unknown_server_ca_accept_verify_none,
     unknown_server_ca_accept_verify_peer,
     unknown_server_ca_accept_backwardscompatibility,
     no_authority_key_identifier].

init_per_suite(Config0) ->
    Dog = ct:timetrap(?LONG_TIMEOUT *2),
    catch crypto:stop(),
    try crypto:start() of
	ok ->
	    application:start(public_key),
	    application:start(ssl),
	    %% make rsa certs using oppenssl
	    Result =
		(catch make_certs:all(?config(data_dir, Config0),
				      ?config(priv_dir, Config0))),
	    ct:print("Make certs  ~p~n", [Result]),

	    Config1 = ssl_test_lib:make_dsa_cert(Config0),
	    Config = ssl_test_lib:cert_options(Config1),
	    [{watchdog, Dog} | Config]
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    ssl:stop(),
    application:stop(crypto).

init_per_group(active, Config) ->
    [{active, true}, {receive_function, send_recv_result_active}  | Config];
init_per_group(active_once, Config) ->
    [{active, once}, {receive_function, send_recv_result_active_once}  | Config];
init_per_group(passive, Config) ->
    [{active, false}, {receive_function, send_recv_result} |  Config];
init_per_group(_, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------

server_verify_peer() ->
    [{doc,"Test server option verify_peer"}].
server_verify_peer(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    Active = ?config(active, Config),
    ReceiveFunction =  ?config(receive_function, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
			   {options, [{active, Active}, {verify, verify_peer}
				      | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
			   {options, [{active, Active} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
server_verify_none() ->
    [{doc,"Test server option verify_none"}].

server_verify_none(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    Active = ?config(active, Config),
    ReceiveFunction =  ?config(receive_function, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
			   {options, [{active, Active}, {verify, verify_none}
				      | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
			   {options, [{active, Active} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------

server_verify_client_once() ->
    [{doc,"Test server option verify_client_once"}].

server_verify_client_once(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_verification_opts, Config),
    Active = ?config(active, Config),
    ReceiveFunction =  ?config(receive_function, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, ReceiveFunction, []}},
					{options, [{active, Active}, {verify, verify_peer},
						   {verify_client_once, true}
						   | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client0 = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, ReceiveFunction, []}},
					{options, [{active, Active} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client0, ok),
    Server ! {listen, {mfa, {ssl_test_lib, no_result, []}}},
    ssl_test_lib:close(Client0),
    Client1 = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {?MODULE, result_ok, []}},
					{options, [{active, Active} | ClientOpts]}]),

    ssl_test_lib:check_result(Client1, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client1).

%%--------------------------------------------------------------------

server_require_peer_cert_ok() ->
    [{doc,"Test server option fail_if_no_peer_cert when peer sends cert"}].

server_require_peer_cert_ok(Config) when is_list(Config) ->
    ServerOpts = [{verify, verify_peer}, {fail_if_no_peer_cert, true}
		  | ?config(server_verification_opts, Config)],
    ClientOpts = ?config(client_verification_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib,send_recv_result, []}},
			   {options, [{active, false} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, send_recv_result, []}},
			   {options, [{active, false} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------

server_require_peer_cert_fail() ->
    [{doc,"Test server option fail_if_no_peer_cert when peer doesn't send cert"}].

server_require_peer_cert_fail(Config) when is_list(Config) ->
    ServerOpts = [{verify, verify_peer}, {fail_if_no_peer_cert, true}
		  | ?config(server_verification_opts, Config)],
    BadClientOpts = ?config(client_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
			   {options, [{active, false} | ServerOpts]}]),

    Port  = ssl_test_lib:inet_port(Server),

    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {options, [{active, false} | BadClientOpts]}]),

    ssl_test_lib:check_result(Server, {error, {tls_alert, "handshake failure"}},
			      Client, {error, {tls_alert, "handshake failure"}}).


%%--------------------------------------------------------------------
verify_fun_always_run_client() ->
    [{doc,"Verify that user verify_fun is always run (for valid and valid_peer not only unknown_extension)"}].

verify_fun_always_run_client(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_verification_opts, Config),
    ServerOpts =  ?config(server_verification_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options, ServerOpts}]),
    Port  = ssl_test_lib:inet_port(Server),

    %% If user verify fun is called correctly we fail the connection.
    %% otherwise we can not tell this case apart form where we miss
    %% to call users verify fun
    FunAndState =  {fun(_,{extension, _}, UserState) ->
			    {unknown, UserState};
		       (_, valid, [ChainLen]) ->
			    {valid, [ChainLen + 1]};
		       (_, valid_peer, [2]) ->
			    {fail, "verify_fun_was_always_run"};
		       (_, valid_peer, UserState) ->
			    {valid, UserState}
		    end, [0]},

    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options,
					       [{verify, verify_peer},
						{verify_fun, FunAndState}
						| ClientOpts]}]),
    %% Server error may be {tls_alert,"handshake failure"} or closed depending on timing
    %% this is not a bug it is a circumstance of how tcp works!
    receive
	{Server, ServerError} ->
	    ct:print("Server Error ~p~n", [ServerError])
    end,

    ssl_test_lib:check_result(Client, {error, {tls_alert, "handshake failure"}}).

%%--------------------------------------------------------------------
verify_fun_always_run_server() ->
    [{doc,"Verify that user verify_fun is always run (for valid and valid_peer not only unknown_extension)"}].
verify_fun_always_run_server(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_verification_opts, Config),
    ServerOpts =  ?config(server_verification_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    %% If user verify fun is called correctly we fail the connection.
    %% otherwise we can not tell this case apart form where we miss
    %% to call users verify fun
    FunAndState =  {fun(_,{extension, _}, UserState) ->
			    {unknown, UserState};
		       (_, valid, [ChainLen]) ->
			    {valid, [ChainLen + 1]};
		       (_, valid_peer, [2]) ->
			    {fail, "verify_fun_was_always_run"};
		       (_, valid_peer, UserState) ->
			    {valid, UserState}
		    end, [0]},

    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options,
					       [{verify, verify_peer},
						{verify_fun, FunAndState} |
						ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),

    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options,
					       [{verify, verify_peer}
						| ClientOpts]}]),

    %% Client error may be {tls_alert, "handshake failure" } or closed depending on timing
    %% this is not a bug it is a circumstance of how tcp works!
    receive
	{Client, ClientError} ->
	    ct:print("Client Error ~p~n", [ClientError])
    end,

    ssl_test_lib:check_result(Server, {error, {tls_alert, "handshake failure"}}).

%%--------------------------------------------------------------------

client_verify_none_passive() ->
    [{doc,"Test client option verify_none"}].

client_verify_none_passive(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result, []}},
					{options, [{active, false}
						   | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),

    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result, []}},
					{options, [{active, false},
						   {verify, verify_none}
						   | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).
%%--------------------------------------------------------------------
cert_expired() ->
    [{doc,"Test server with expired certificate"}].

cert_expired(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    PrivDir = ?config(priv_dir, Config),

    KeyFile = filename:join(PrivDir, "otpCA/private/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    ServerCertFile = proplists:get_value(certfile, ServerOpts),
    NewServerCertFile = filename:join(PrivDir, "server/expired_cert.pem"),
    [{'Certificate', DerCert, _}] = ssl_test_lib:pem_to_der(ServerCertFile),
    OTPCert = public_key:pkix_decode_cert(DerCert, otp),
    OTPTbsCert = OTPCert#'OTPCertificate'.tbsCertificate,

    {Year, Month, Day} = date(),
    {Hours, Min, Sec} = time(),
    NotBeforeStr = lists:flatten(io_lib:format("~p~s~s~s~s~sZ",[Year-2,
								two_digits_str(Month),
								two_digits_str(Day),
								two_digits_str(Hours),
								two_digits_str(Min),
								two_digits_str(Sec)])),
    NotAfterStr = lists:flatten(io_lib:format("~p~s~s~s~s~sZ",[Year-1,
							       two_digits_str(Month),
							       two_digits_str(Day),
							       two_digits_str(Hours),
							       two_digits_str(Min),
							       two_digits_str(Sec)])),
    NewValidity = {'Validity', {generalTime, NotBeforeStr}, {generalTime, NotAfterStr}},

    ct:print("Validity: ~p ~n NewValidity: ~p ~n",
		       [OTPTbsCert#'OTPTBSCertificate'.validity, NewValidity]),

    NewOTPTbsCert =  OTPTbsCert#'OTPTBSCertificate'{validity = NewValidity},
    NewServerDerCert = public_key:pkix_sign(NewOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewServerCertFile, [{'Certificate', NewServerDerCert, not_encrypted}]),
    NewServerOpts = [{certfile, NewServerCertFile} | proplists:delete(certfile, ServerOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, NewServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {options, [{verify, verify_peer} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, {error, {tls_alert, "certificate expired"}},
			      Client, {error, {tls_alert, "certificate expired"}}).

two_digits_str(N) when N < 10 ->
    lists:flatten(io_lib:format("0~p", [N]));
two_digits_str(N) ->
    lists:flatten(io_lib:format("~p", [N])).

%%--------------------------------------------------------------------

client_verify_none_active() ->
    [{doc,"Test client option verify_none"}].

client_verify_none_active(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, [{active, true}
						   | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, [{active, true},
						   {verify, verify_none}
						   | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
client_verify_none_active_once() ->
    [{doc,"Test client option verify_none"}].

client_verify_none_active_once(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib, send_recv_result_active, []}},
			   {options, [{active, once} | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),

    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active_once,
					       []}},
					{options, [{active, once},
						   {verify, verify_none}
						   | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
extended_key_usage_verify_peer() ->
    [{doc,"Test cert that has a critical extended_key_usage extension in verify_peer mode"}].

extended_key_usage_verify_peer(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    PrivDir = ?config(priv_dir, Config),
    Active = ?config(active, Config),
    ReceiveFunction =  ?config(receive_function, Config),

    KeyFile = filename:join(PrivDir, "otpCA/private/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    ServerCertFile = proplists:get_value(certfile, ServerOpts),
    NewServerCertFile = filename:join(PrivDir, "server/new_cert.pem"),
    [{'Certificate', ServerDerCert, _}] = ssl_test_lib:pem_to_der(ServerCertFile),
    ServerOTPCert = public_key:pkix_decode_cert(ServerDerCert, otp),
    ServerExtKeyUsageExt = {'Extension', ?'id-ce-extKeyUsage', true, [?'id-kp-serverAuth']},
    ServerOTPTbsCert = ServerOTPCert#'OTPCertificate'.tbsCertificate,
    ServerExtensions =  ServerOTPTbsCert#'OTPTBSCertificate'.extensions,
    NewServerOTPTbsCert = ServerOTPTbsCert#'OTPTBSCertificate'{extensions =
							       [ServerExtKeyUsageExt |
								ServerExtensions]},
    NewServerDerCert = public_key:pkix_sign(NewServerOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewServerCertFile, [{'Certificate', NewServerDerCert, not_encrypted}]),
    NewServerOpts = [{certfile, NewServerCertFile} | proplists:delete(certfile, ServerOpts)],

    ClientCertFile = proplists:get_value(certfile, ClientOpts),
    NewClientCertFile = filename:join(PrivDir, "client/new_cert.pem"),
    [{'Certificate', ClientDerCert, _}] = ssl_test_lib:pem_to_der(ClientCertFile),
    ClientOTPCert = public_key:pkix_decode_cert(ClientDerCert, otp),
    ClientExtKeyUsageExt = {'Extension', ?'id-ce-extKeyUsage', true, [?'id-kp-clientAuth']},
    ClientOTPTbsCert = ClientOTPCert#'OTPCertificate'.tbsCertificate,
    ClientExtensions =  ClientOTPTbsCert#'OTPTBSCertificate'.extensions,
    NewClientOTPTbsCert = ClientOTPTbsCert#'OTPTBSCertificate'{extensions =
							       [ClientExtKeyUsageExt |
								ClientExtensions]},
    NewClientDerCert = public_key:pkix_sign(NewClientOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewClientCertFile, [{'Certificate', NewClientDerCert, not_encrypted}]),
    NewClientOpts = [{certfile, NewClientCertFile} | proplists:delete(certfile, ClientOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib,  ReceiveFunction, []}},
			   {options, [{verify, verify_peer}, {active, Active} | NewServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
					{options, [{verify, verify_peer}, {active, Active} |
						   NewClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
extended_key_usage_verify_none() ->
    [{doc,"Test cert that has a critical extended_key_usage extension in verify_none mode"}].

extended_key_usage_verify_none(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    PrivDir = ?config(priv_dir, Config),
    Active = ?config(active, Config),
    ReceiveFunction =  ?config(receive_function, Config),

    KeyFile = filename:join(PrivDir, "otpCA/private/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    ServerCertFile = proplists:get_value(certfile, ServerOpts),
    NewServerCertFile = filename:join(PrivDir, "server/new_cert.pem"),
    [{'Certificate', ServerDerCert, _}] = ssl_test_lib:pem_to_der(ServerCertFile),
    ServerOTPCert = public_key:pkix_decode_cert(ServerDerCert, otp),
    ServerExtKeyUsageExt = {'Extension', ?'id-ce-extKeyUsage', true, [?'id-kp-serverAuth']},
    ServerOTPTbsCert = ServerOTPCert#'OTPCertificate'.tbsCertificate,
    ServerExtensions =  ServerOTPTbsCert#'OTPTBSCertificate'.extensions,
    NewServerOTPTbsCert = ServerOTPTbsCert#'OTPTBSCertificate'{extensions =
							       [ServerExtKeyUsageExt |
								ServerExtensions]},
    NewServerDerCert = public_key:pkix_sign(NewServerOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewServerCertFile, [{'Certificate', NewServerDerCert, not_encrypted}]),
    NewServerOpts = [{certfile, NewServerCertFile} | proplists:delete(certfile, ServerOpts)],

    ClientCertFile = proplists:get_value(certfile, ClientOpts),
    NewClientCertFile = filename:join(PrivDir, "client/new_cert.pem"),
    [{'Certificate', ClientDerCert, _}] = ssl_test_lib:pem_to_der(ClientCertFile),
    ClientOTPCert = public_key:pkix_decode_cert(ClientDerCert, otp),
    ClientExtKeyUsageExt = {'Extension', ?'id-ce-extKeyUsage', true, [?'id-kp-clientAuth']},
    ClientOTPTbsCert = ClientOTPCert#'OTPCertificate'.tbsCertificate,
    ClientExtensions =  ClientOTPTbsCert#'OTPTBSCertificate'.extensions,
    NewClientOTPTbsCert = ClientOTPTbsCert#'OTPTBSCertificate'{extensions =
								   [ClientExtKeyUsageExt |
								    ClientExtensions]},
    NewClientDerCert = public_key:pkix_sign(NewClientOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewClientCertFile, [{'Certificate', NewClientDerCert, not_encrypted}]),
    NewClientOpts = [{certfile, NewClientCertFile} | proplists:delete(certfile, ClientOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
			   {options, [{verify, verify_none}, {active, Active} | NewServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, ReceiveFunction, []}},
					{options, [{verify, verify_none}, {active, Active} | NewClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
no_authority_key_identifier() ->
    [{doc, "Test cert that does not have authorityKeyIdentifier extension"
      " but are present in trusted certs db."}].

no_authority_key_identifier(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_opts, Config),
    PrivDir = ?config(priv_dir, Config),

    KeyFile = filename:join(PrivDir, "otpCA/private/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    CertFile = proplists:get_value(certfile, ServerOpts),
    NewCertFile = filename:join(PrivDir, "server/new_cert.pem"),
    [{'Certificate', DerCert, _}] = ssl_test_lib:pem_to_der(CertFile),
    OTPCert = public_key:pkix_decode_cert(DerCert, otp),
    OTPTbsCert = OTPCert#'OTPCertificate'.tbsCertificate,
    Extensions =  OTPTbsCert#'OTPTBSCertificate'.extensions,
    NewExtensions =  delete_authority_key_extension(Extensions, []),
    NewOTPTbsCert =  OTPTbsCert#'OTPTBSCertificate'{extensions = NewExtensions},

    ct:print("Extensions ~p~n, NewExtensions: ~p~n", [Extensions, NewExtensions]),

    NewDerCert = public_key:pkix_sign(NewOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewCertFile, [{'Certificate', NewDerCert, not_encrypted}]),
    NewServerOpts = [{certfile, NewCertFile} | proplists:delete(certfile, ServerOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
			   {mfa, {ssl_test_lib, send_recv_result_active, []}},
			   {options, NewServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
			   {from, self()},
			   {mfa, {ssl_test_lib, send_recv_result_active, []}},
			   {options, [{verify, verify_peer} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

delete_authority_key_extension([], Acc) ->
    lists:reverse(Acc);
delete_authority_key_extension([#'Extension'{extnID = ?'id-ce-authorityKeyIdentifier'} | Rest],
			       Acc) ->
    delete_authority_key_extension(Rest, Acc);
delete_authority_key_extension([Head | Rest], Acc) ->
    delete_authority_key_extension(Rest, [Head | Acc]).

%%--------------------------------------------------------------------

invalid_signature_server() ->
    [{doc,"Test client with invalid signature"}].

invalid_signature_server(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    PrivDir = ?config(priv_dir, Config),

    KeyFile = filename:join(PrivDir, "server/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    ServerCertFile = proplists:get_value(certfile, ServerOpts),
    NewServerCertFile = filename:join(PrivDir, "server/invalid_cert.pem"),
    [{'Certificate', ServerDerCert, _}] = ssl_test_lib:pem_to_der(ServerCertFile),
    ServerOTPCert = public_key:pkix_decode_cert(ServerDerCert, otp),
    ServerOTPTbsCert = ServerOTPCert#'OTPCertificate'.tbsCertificate,
    NewServerDerCert = public_key:pkix_sign(ServerOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewServerCertFile, [{'Certificate', NewServerDerCert, not_encrypted}]),
    NewServerOpts = [{certfile, NewServerCertFile} | proplists:delete(certfile, ServerOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, NewServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {options, [{verify, verify_peer} | ClientOpts]}]),

    tcp_delivery_workaround(Server, {error, {tls_alert, "bad certificate"}},
			    Client, {error, {tls_alert, "bad certificate"}}).

%%--------------------------------------------------------------------

invalid_signature_client() ->
    [{doc,"Test server with invalid signature"}].

invalid_signature_client(Config) when is_list(Config) ->
    ClientOpts = ?config(client_verification_opts, Config),
    ServerOpts = ?config(server_verification_opts, Config),
    PrivDir = ?config(priv_dir, Config),

    KeyFile = filename:join(PrivDir, "client/key.pem"),
    [KeyEntry] = ssl_test_lib:pem_to_der(KeyFile),
    Key = ssl_test_lib:public_key(public_key:pem_entry_decode(KeyEntry)),

    ClientCertFile = proplists:get_value(certfile, ClientOpts),
    NewClientCertFile = filename:join(PrivDir, "client/invalid_cert.pem"),
    [{'Certificate', ClientDerCert, _}] = ssl_test_lib:pem_to_der(ClientCertFile),
    ClientOTPCert = public_key:pkix_decode_cert(ClientDerCert, otp),
    ClientOTPTbsCert = ClientOTPCert#'OTPCertificate'.tbsCertificate,
    NewClientDerCert = public_key:pkix_sign(ClientOTPTbsCert, Key),
    ssl_test_lib:der_to_pem(NewClientCertFile, [{'Certificate', NewClientDerCert, not_encrypted}]),
    NewClientOpts = [{certfile, NewClientCertFile} | proplists:delete(certfile, ClientOpts)],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					{from, self()},
					{options, [{verify, verify_peer} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {options, NewClientOpts}]),

    tcp_delivery_workaround(Server, {error, {tls_alert, "bad certificate"}},
			    Client, {error, {tls_alert, "bad certificate"}}).


%%--------------------------------------------------------------------

client_with_cert_cipher_suites_handshake() ->
    [{doc, "Test that client with a certificate without keyEncipherment usage "
    " extension can connect to a server with restricted cipher suites "}].
client_with_cert_cipher_suites_handshake(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_verification_opts_digital_signature_only, Config),
    ServerOpts =  ?config(server_verification_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, [{active, true},
						   {ciphers, ssl_test_lib:rsa_non_signed_suites()}
						   | ServerOpts]}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, [{active, true}
						   | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------

server_verify_no_cacerts() ->
    [{doc,"Test server must have cacerts if it wants to verify client"}].
server_verify_no_cacerts(Config) when is_list(Config) ->
    ServerOpts =  ?config(server_opts, Config),
    {_, ServerNode, _} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {options, [{verify, verify_peer}
							 | ServerOpts]}]),

    ssl_test_lib:check_result(Server, {error, {options, {cacertfile, ""}}}).


%%--------------------------------------------------------------------
unknown_server_ca_fail() ->
    [{doc,"Test that the client fails if the ca is unknown in verify_peer mode"}].
unknown_server_ca_fail(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options, ServerOpts}]),
    Port  = ssl_test_lib:inet_port(Server),

    FunAndState =  {fun(_,{bad_cert, unknown_ca} = Reason, _) ->
			    {fail, Reason};
		       (_,{extension, _}, UserState) ->
			    {unknown, UserState};
		       (_, valid, UserState) ->
			    {valid, [test_to_update_user_state | UserState]};
		       (_, valid_peer, UserState) ->
			    {valid, UserState}
		    end, []},

    Client = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port},
					      {host, Hostname},
					      {from, self()},
					      {mfa, {ssl_test_lib,
						     no_result, []}},
					      {options,
					       [{verify, verify_peer},
						{verify_fun, FunAndState}
						| ClientOpts]}]),

    ssl_test_lib:check_result(Server, {error, {tls_alert, "unknown ca"}},
			      Client, {error, {tls_alert, "unknown ca"}}).

%%--------------------------------------------------------------------
unknown_server_ca_accept_verify_none() ->
    [{doc,"Test that the client succeds if the ca is unknown in verify_none mode"}].
unknown_server_ca_accept_verify_none(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port  = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options,
					 [{verify, verify_none}| ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).
%%--------------------------------------------------------------------
unknown_server_ca_accept_verify_peer() ->
    [{doc, "Test that the client succeds if the ca is unknown in verify_peer mode"
     " with a verify_fun that accepts the unknown ca error"}].
unknown_server_ca_accept_verify_peer(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port  = ssl_test_lib:inet_port(Server),

    FunAndState =  {fun(_,{bad_cert, unknown_ca}, UserState) ->
			    {valid, UserState};
		       (_,{bad_cert, _} = Reason, _) ->
			    {fail, Reason};
		       (_,{extension, _}, UserState) ->
			    {unknown, UserState};
		       (_, valid, UserState) ->
			    {valid, UserState};
		       (_, valid_peer, UserState) ->
			    {valid, UserState}
		    end, []},

    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options,
					 [{verify, verify_peer},
					  {verify_fun, FunAndState}| ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
unknown_server_ca_accept_backwardscompatibility() ->
    [{doc,"Test that old style verify_funs will work"}].
unknown_server_ca_accept_backwardscompatibility(Config) when is_list(Config) ->
    ClientOpts =  ?config(client_opts, Config),
    ServerOpts =  ?config(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port  = ssl_test_lib:inet_port(Server),

    AcceptBadCa = fun({bad_cert,unknown_ca}, Acc) ->  Acc;
		     (Other, Acc) -> [Other | Acc]
		  end,
    VerifyFun =
	fun(ErrorList) ->
		case lists:foldl(AcceptBadCa, [], ErrorList) of
		    [] ->    true;
		    [_|_] -> false
		end
	end,

    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib,
					       send_recv_result_active, []}},
					{options,
					 [{verify, verify_peer},
					  {verify_fun, VerifyFun}| ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

%%--------------------------------------------------------------------
%% Internal functions ------------------------------------------------
%%--------------------------------------------------------------------

tcp_delivery_workaround(Server, ServerMsg, Client, ClientMsg) ->
    receive
	{Server, ServerMsg} ->
	    client_msg(Client, ClientMsg);
	{Client, ClientMsg} ->
	    server_msg(Server, ServerMsg);
	{Client, {error,closed}} ->
	    server_msg(Server, ServerMsg);
	{Server, {error,closed}} ->
	    client_msg(Client, ClientMsg)
    end.

client_msg(Client, ClientMsg) ->
    receive
	{Client, ClientMsg} ->
	    ok;
	{Client, {error,closed}} ->
	    ct:print("client got close"),
	    ok;
	{Client, {error, Reason}} ->
	    ct:print("client got econnaborted: ~p", [Reason]),
	    ok;
	Unexpected ->
	    ct:fail(Unexpected)
    end.
server_msg(Server, ServerMsg) ->
    receive
	{Server, ServerMsg} ->
	    ok;
	{Server, {error,closed}} ->
	    ct:print("server got close"),
	    ok;
	{Server, {error, Reason}} ->
	    ct:print("server got econnaborted: ~p", [Reason]),
	    ok;
	Unexpected ->
	    ct:fail(Unexpected)
    end.
