<script lang="ts">
	import { services, sections } from '$lib/data/services';
	import Card from '$lib/components/Card.svelte';
</script>

<div class="container">
	<header>
		<div class="logo"><span>veron3</span>.space</div>
		<p class="subtitle">Projects — Hetzner NBG1</p>
	</header>

	{#each sections as { key, label }}
		{@const sectionServices = services.filter(s => s.section === key)}
		{@const ungrouped = sectionServices.filter(s => !s.group)}
		{@const groups = [...new Set(sectionServices.filter(s => s.group).map(s => s.group!))]}
		{#if sectionServices.length > 0}
			<div class="section">
				<div class="section-label">{label}</div>
				{#if ungrouped.length > 0}
					<div class="grid">
						{#each ungrouped as service (service.code)}
							<Card {service} />
						{/each}
					</div>
				{/if}
				{#each groups as group}
					{@const groupServices = sectionServices.filter(s => s.group === group)}
					<div class="group">
						<div class="group-label">{group}</div>
						<div class="grid">
							{#each groupServices as service (service.code)}
								<Card {service} />
							{/each}
						</div>
					</div>
				{/each}
			</div>
		{/if}
	{/each}

	<footer>veron3.space &middot; NBG1 &middot; Ubuntu 24.04</footer>
</div>
