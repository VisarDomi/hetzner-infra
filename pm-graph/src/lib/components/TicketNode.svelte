<script lang="ts">
	import type { GraphNode } from '$lib/types';

	let { node }: { node: GraphNode } = $props();

	const PLANE_URL = 'https://pm.veron3.space/veron3/browse';
</script>

<a
	href="{PLANE_URL}/{node.id}/"
	target="_blank"
	rel="noopener"
	class="node priority-{node.priority}"
	title={node.title}
>
	<span class="node-id">{node.id}</span>
	<span class="node-title">{node.title}</span>
</a>
