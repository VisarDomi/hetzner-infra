<script lang="ts">
	import type { PlaneData } from '$lib/types';
	import { buildGraph, buildNodeMap, countStats } from '$lib/graph';
	import ProjectGroupComponent from './ProjectGroup.svelte';

	let { data }: { data: PlaneData } = $props();

	const nodeMap = $derived(buildNodeMap(data.issues));
	const groups = $derived(buildGraph(data.issues, data.relations));
	const stats = $derived(countStats(data.relations));

	const issuesWithRelations = $derived(
		new Set([
			...data.relations.map((r) => r.source),
			...data.relations.map((r) => r.target)
		]).size
	);
</script>

<div class="stats">
	{issuesWithRelations} tickets with relations &middot; {stats.blockers} blockers &middot; {stats.related} related &middot; {data.total} total open
</div>

<div class="legend">
	<div class="legend-item"><div class="legend-color urgent"></div> Urgent</div>
	<div class="legend-item"><div class="legend-color high"></div> High</div>
	<div class="legend-item"><div class="legend-color medium"></div> Medium</div>
	<div class="legend-item"><div class="legend-color low"></div> Low</div>
	<div class="legend-item"><div class="legend-color none"></div> None</div>
	<div class="legend-item"><span class="arrow">&rarr;</span> blocks</div>
	<div class="legend-item"><span class="arrow relates">&harr;</span> relates to</div>
</div>

{#if groups.length === 0}
	<div class="loading">No dependency relations found.</div>
{:else}
	<div class="graph-container">
		{#each groups as group (group.name)}
			<ProjectGroupComponent {group} {nodeMap} />
		{/each}
	</div>
{/if}

{#if data.errors.length > 0}
	<details style="margin-top: 24px; color: var(--text-muted); font-size: 12px;">
		<summary>{data.errors.length} warning(s)</summary>
		<ul style="margin-top: 8px; padding-left: 20px;">
			{#each data.errors as err}
				<li>{err}</li>
			{/each}
		</ul>
	</details>
{/if}
