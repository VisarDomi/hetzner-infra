<script lang="ts">
	import type { Service } from '$lib/data/services';

	let { service }: { service: Service } = $props();

	function onMouseMove(e: MouseEvent) {
		const card = e.currentTarget as HTMLElement;
		const r = card.getBoundingClientRect();
		card.style.setProperty('--x', (e.clientX - r.left) + 'px');
		card.style.setProperty('--y', (e.clientY - r.top) + 'px');
	}

	const tagClass = $derived(
		service.status === 'live' ? 'tag-live' :
		service.status === 'dev' ? 'tag-dev' : 'tag-idea'
	);

	const tagLabel = $derived(
		service.status === 'live' ? 'Live' :
		service.status === 'dev' ? 'In Dev' : 'Idea'
	);

	const isMuted = $derived(service.status === 'idea');
</script>

<a
	href={service.url}
	class="card"
	class:muted={isMuted}
	target="_blank"
	rel="noopener"
	onmousemove={isMuted ? undefined : onMouseMove}
>
	<div class="card-top">
		<div class="icon">{service.icon}</div>
		<div class="card-info">
			<h2>{service.name}</h2>
			<div class="mono">{service.code}</div>
		</div>
	</div>
	<p>{service.description}</p>
	<div class="card-bottom">
		<span class="tag {tagClass}">{tagLabel}</span>
		{#if service.domain}
			<span class="domain">{service.domain}</span>
		{/if}
	</div>
</a>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: 10px;
		background: #111113;
		border: 1px solid #1e1e22;
		border-radius: 14px;
		padding: 22px;
		text-decoration: none;
		color: inherit;
		transition: border-color 0.2s, background 0.2s, transform 0.2s, box-shadow 0.2s;
		position: relative;
		overflow: hidden;
	}

	.card::before {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: 14px;
		opacity: 0;
		background: radial-gradient(600px circle at var(--x, 50%) var(--y, 50%), rgba(129,140,248,0.04), transparent 40%);
		transition: opacity 0.3s;
		pointer-events: none;
	}

	.card:hover::before { opacity: 1; }

	.card:hover {
		border-color: #27272a;
		background: #141416;
		transform: translateY(-1px);
		box-shadow: 0 4px 20px rgba(0,0,0,0.4);
	}

	.card.muted {
		opacity: 0.35;
		pointer-events: none;
	}

	.card-top {
		display: flex;
		align-items: center;
		gap: 14px;
	}

	.icon {
		font-size: 24px;
		width: 42px;
		height: 42px;
		background: rgba(255,255,255,0.04);
		border-radius: 11px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.card-info { flex: 1; min-width: 0; }

	.card-info h2 {
		font-size: 15px;
		font-weight: 600;
		letter-spacing: -0.2px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.card-info .mono {
		font-family: 'JetBrains Mono', 'SF Mono', Consolas, monospace;
		font-size: 11px;
		color: #3f3f46;
		margin-top: 2px;
	}

	.card p {
		font-size: 13px;
		color: #71717a;
		line-height: 1.55;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}

	.card-bottom {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-top: auto;
		padding-top: 6px;
	}

	.tag {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.6px;
		padding: 3px 9px;
		border-radius: 6px;
	}

	.tag-live { background: rgba(74,222,128,0.1); color: #4ade80; }
	.tag-dev  { background: rgba(96,165,250,0.1); color: #60a5fa; }
	.tag-idea { background: rgba(161,161,170,0.06); color: #52525b; }

	.domain {
		font-family: 'JetBrains Mono', 'SF Mono', Consolas, monospace;
		font-size: 11px;
		color: #3f3f46;
	}
</style>
