<script lang="ts">
	import '$lib/styles.css';
	import { onMount } from 'svelte';

	let { children } = $props();

	onMount(() => {
		if ('serviceWorker' in navigator) {
			navigator.serviceWorker.register('/sw.js');
		}
	});
</script>

<svelte:head>
	<title>veron3 — Projects</title>
</svelte:head>

{@render children()}
