-- Mission rewards are already earned cargo, batched independently of rockets.
if not mods['space-age'] then return end
local reward_pod = table.deepcopy(data.raw['cargo-pod']['cargo-pod'])
reward_pod.name = 'mts-expanse-reward-pod'
reward_pod.localised_name = {'entity-name.cargo-pod'}
reward_pod.inventory_size = 80
local container = table.deepcopy(data.raw['temporary-container']['cargo-pod-container'])
container.name = 'mts-expanse-reward-pod-container'
container.localised_name = {'entity-name.cargo-pod-container'}
container.inventory_size = reward_pod.inventory_size
reward_pod.spawned_container = container.name
data:extend{reward_pod, container}
