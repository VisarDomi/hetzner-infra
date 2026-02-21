export interface Issue {
	id: string;
	project: string;
	project_name: string;
	title: string;
	priority: 'urgent' | 'high' | 'medium' | 'low' | 'none';
	state: string;
	state_group: string;
	created: string;
	updated: string;
}

export interface Relation {
	source: string;
	type: 'blocked_by' | 'relates_to';
	target: string;
	target_title: string;
}

export interface PlaneData {
	issues: Issue[];
	relations: Relation[];
	errors: string[];
	total: number;
}

export interface GraphNode {
	id: string;
	title: string;
	project: string;
	priority: Issue['priority'];
	state: string;
}

export interface Chain {
	nodes: string[];
}

export interface ProjectGroup {
	name: string;
	blockerChains: Chain[];
	relatesEdges: Relation[];
}
