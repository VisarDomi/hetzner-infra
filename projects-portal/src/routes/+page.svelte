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
		{#if sectionServices.length > 0}
			<div class="section">
				<div class="section-label">{label}</div>
				<div class="grid">
					{#each sectionServices as service (service.code)}
						<Card {service} />
					{/each}
				</div>
			</div>
		{/if}
	{/each}

	<footer>veron3.space &middot; NBG1 &middot; Ubuntu 24.04</footer>
</div>
