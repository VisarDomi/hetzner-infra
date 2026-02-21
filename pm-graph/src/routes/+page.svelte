<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { PlaneData } from '$lib/types';
	import DependencyGraph from '$lib/components/DependencyGraph.svelte';

	let data: PlaneData | null = $state(null);
	let error: string | null = $state(null);
	let loading = $state(true);
	let refreshing = $state(false);
	let lastUpdated: string | null = $state(null);
	let interval: ReturnType<typeof setInterval> | undefined;

	// Pull-to-refresh state
	let touchStartY = 0;
	let pullDistance = $state(0);
	const PULL_THRESHOLD = 80;

	async function fetchData() {
		try {
			const res = await fetch('/data.json', { cache: 'no-cache' });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			data = await res.json();
			error = null;
			lastUpdated = new Date().toLocaleTimeString();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load data';
		} finally {
			loading = false;
			refreshing = false;
			pullDistance = 0;
		}
	}

	function handleTouchStart(e: TouchEvent) {
		if (window.scrollY === 0) {
			touchStartY = e.touches[0].clientY;
		}
	}

	function handleTouchMove(e: TouchEvent) {
		if (touchStartY === 0) return;
		const diff = e.touches[0].clientY - touchStartY;
		if (diff > 0 && window.scrollY === 0) {
			pullDistance = Math.min(diff * 0.5, PULL_THRESHOLD + 20);
		}
	}

	function handleTouchEnd() {
		if (pullDistance >= PULL_THRESHOLD && !refreshing) {
			refreshing = true;
			fetchData();
		} else {
			pullDistance = 0;
		}
		touchStartY = 0;
	}

	onMount(() => {
		fetchData();
		interval = setInterval(fetchData, 5 * 60 * 1000); // 5 minutes
	});

	onDestroy(() => {
		if (interval) clearInterval(interval);
	});
</script>

<svelte:window
	ontouchstart={handleTouchStart}
	ontouchmove={handleTouchMove}
	ontouchend={handleTouchEnd}
/>

<div class="refresh-indicator" class:active={refreshing}></div>

{#if pullDistance > 0}
	<div style="text-align: center; padding: {pullDistance}px 0 0; color: var(--text-muted); font-size: 12px; transition: padding 0.1s;">
		{pullDistance >= PULL_THRESHOLD ? 'Release to refresh' : 'Pull to refresh'}
	</div>
{/if}

<div class="container">
	<header>
		<h1>Plane Dependency Graph</h1>
		{#if lastUpdated}
			<div class="last-updated">Updated {lastUpdated}</div>
		{/if}
	</header>

	{#if loading}
		<div class="loading">Loading dependency graph...</div>
	{:else if error}
		<div class="error">
			{error}
			<br /><br />
			<button onclick={fetchData} style="color: var(--accent); background: none; border: 1px solid var(--accent); padding: 8px 16px; border-radius: 6px; cursor: pointer;">
				Retry
			</button>
		</div>
	{:else if data}
		<DependencyGraph {data} />
	{/if}

	<footer>pm-graph.veron3.space</footer>
</div>
