import type { Issue, Relation, GraphNode, Chain, ProjectGroup } from './types';

export function buildNodeMap(issues: Issue[]): Map<string, GraphNode> {
	const map = new Map<string, GraphNode>();
	for (const issue of issues) {
		map.set(issue.id, {
			id: issue.id,
			title: issue.title,
			project: issue.project,
			priority: issue.priority,
			state: issue.state
		});
	}
	return map;
}

export function buildGraph(
	issues: Issue[],
	relations: Relation[]
): ProjectGroup[] {
	const nodeMap = buildNodeMap(issues);
	const blockers = relations.filter((r) => r.type === 'blocked_by');
	const relates = relations.filter((r) => r.type === 'relates_to');

	// Build adjacency list for blocker chains
	const adj = new Map<string, string[]>();
	for (const e of blockers) {
		const list = adj.get(e.source) || [];
		list.push(e.target);
		adj.set(e.source, list);
	}

	// Find chain roots (sources that aren't targets of any blocker)
	const allTargets = new Set(blockers.map((e) => e.target));
	const allSources = new Set(blockers.map((e) => e.source));
	const roots = [...allSources].filter((s) => !allTargets.has(s));

	const visited = new Set<string>();
	const chains: Chain[] = [];

	function buildChain(node: string): string[] {
		const chain = [node];
		visited.add(node);
		const next = adj.get(node) || [];
		for (const t of next) {
			if (!visited.has(t)) {
				chain.push(...buildChain(t));
			}
		}
		return chain;
	}

	// Build chains from roots
	for (const r of roots) {
		if (!visited.has(r)) {
			chains.push({ nodes: buildChain(r) });
		}
	}

	// Catch remaining blockers not in chains
	for (const e of blockers) {
		if (!visited.has(e.source)) {
			visited.add(e.source);
			visited.add(e.target);
			chains.push({ nodes: [e.source, e.target] });
		} else if (!visited.has(e.target)) {
			visited.add(e.target);
			for (const c of chains) {
				if (c.nodes.includes(e.source)) {
					c.nodes.push(e.target);
					break;
				}
			}
		}
	}

	// Group chains by project
	const projectGroups = new Map<string, { blockerChains: Chain[]; relatesEdges: Relation[] }>();

	for (const chain of chains) {
		const projects = new Set(
			chain.nodes.map((id) => nodeMap.get(id)?.project).filter(Boolean)
		);
		const key = projects.size > 1 ? 'Cross-project' : (nodeMap.get(chain.nodes[0])?.project || 'Other');
		if (!projectGroups.has(key)) {
			projectGroups.set(key, { blockerChains: [], relatesEdges: [] });
		}
		projectGroups.get(key)!.blockerChains.push(chain);
	}

	for (const r of relates) {
		const p1 = nodeMap.get(r.source)?.project;
		const p2 = nodeMap.get(r.target)?.project;
		const key = p1 === p2 ? (p1 || 'Other') : 'Cross-project';
		if (!projectGroups.has(key)) {
			projectGroups.set(key, { blockerChains: [], relatesEdges: [] });
		}
		projectGroups.get(key)!.relatesEdges.push(r);
	}

	// Sort: Cross-project first, then alphabetical
	const order = [
		'Cross-project',
		...[...projectGroups.keys()].filter((k) => k !== 'Cross-project').sort()
	];

	const result: ProjectGroup[] = [];
	for (const name of order) {
		const group = projectGroups.get(name);
		if (group) {
			result.push({ name, ...group });
		}
	}

	return result;
}

export function countStats(relations: Relation[]): { blockers: number; related: number } {
	let blockers = 0;
	let related = 0;
	for (const r of relations) {
		if (r.type === 'blocked_by') blockers++;
		else related++;
	}
	return { blockers, related };
}
