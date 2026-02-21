<script lang="ts">
	import type { ProjectGroup } from '$lib/types';
	import type { GraphNode } from '$lib/types';
	import TicketNode from './TicketNode.svelte';

	let { group, nodeMap }: { group: ProjectGroup; nodeMap: Map<string, GraphNode> } = $props();

	function getNode(id: string): GraphNode {
		return nodeMap.get(id) || { id, title: id, project: '', priority: 'none', state: '' };
	}
</script>

<div class="chain-group">
	<h2>{group.name}</h2>

	{#each group.blockerChains as chain}
		<div class="chain">
			{#each chain.nodes as id, i}
				<TicketNode node={getNode(id)} />
				{#if i < chain.nodes.length - 1}
					<span class="arrow">&rarr;</span>
				{/if}
			{/each}
		</div>
	{/each}

	{#each group.relatesEdges as rel}
		<div class="chain">
			<TicketNode node={getNode(rel.source)} />
			<span class="arrow relates">&harr;</span>
			<TicketNode node={getNode(rel.target)} />
		</div>
	{/each}
</div>
