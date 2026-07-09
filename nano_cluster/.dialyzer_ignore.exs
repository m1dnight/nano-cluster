# Calls into modules that only exist on the AtomVM device image
# (:esp, :network, :epmd, and AtomVM's :net_kernel.set_cookie/1).
[
  {"lib/nano_cluster/distribution.ex", :unknown_function},
  {"lib/nano_cluster/distribution.ex", :call_to_missing},
  {"lib/nano_cluster/wifi.ex", :unknown_function},
  {"lib/set_network_config.ex", :unknown_function}
]
