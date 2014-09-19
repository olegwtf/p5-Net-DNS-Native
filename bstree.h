typedef struct {
	bstree_node *root;
	int size;
} bstree;

bstree* bstree_new() {
	bstree *tree = malloc(sizeof(bstree));
	tree->size = 0;
	tree->root = NULL;
	
	return tree;
}

void bstree_put(bstree *tree, int key, void *val) {
	_bstree_put(tree->root, key, val);
}

void* bstree_get(bstree *tree, int key) {
	return _bstree_get(tree->root, key);
}

void bstree_del(bstree *tree, int key) {
	_bstree_del(NULL, tree->root, key);
}

void bstree_destroy(bstree *tree) {
	_bstree_destroy(tree->root);
	free(tree);
}

// PRIVATE API

typedef struct {
	int key;
	void *val;
	bstree_node *left;
	bstree_node *right;
} bstree_node;

int bstree_size(bstree *tree) {
	return tree->size;
}

bstree_node* _bstree_new_node(int key, void *val) {
	bstree_node *node = malloc(sizeof(bstree_node));
	node->left = node->right = NULL;
	node->key = key;
	node->val = val;
	
	return node;
}

void _bstree_put(bstree_node *node, int key, void *val) {
	if (node == NULL) {
		node = _bstree_new_node(key, val);
		return;
	}
	
	if (key > node->key)
		return _bstree_put(node->right, key, val);
	
	if (key < node->key)
		return _bstree_put(node->left, key, val);
	
	node->key = key;
	node->val = val;
}

void* _bstree_get(bstree_node *node, int key) {
	if (node == NULL)
		return NULL
	
	if (node->key == key)
		return node->val;
	
	if (key > node->key)
		return _bstree_get(node->right, key);
	
	return _bstree_get(node->left, key);
}

void _bstree_del(bstree_node *parent, bstree_node *node, int key) {
	if (node == NULL)
		return;
	
	if (key > node->key)
		return _bstree_del(node, node->right, key);
	
	if (key < node->key)
		return _bstree_del(node, node->left, key);
	
	if (parent == NULL)
		goto RET;
	
	if (node->left == NULL && node->right == NULL) {
		if (parent->left == node) {
			parent->left = NULL;
		}
		else {
			parent->right = NULL;
		}
		
		goto RET;
	}
	
	if (node->left == NULL) {
		if (parent->left == node) {
			parent->left = node->right;
		}
		else {
			parent->right = node->right;
		}
		
		goto RET;
	}
	
	if (node->right == NULL) {
		if (parent->left == node) {
			parent->left = node->left;
		}
		else {
			parent->right = node->left;
		}
		
		goto RET;
	}
	
	// get the most left element from right node
	// swap key and value with node
	// delete this element instead of node
	
	RET:
		free(node);
}

void _bstree_destroy(bstree_node *node) {
	if (node == NULL)
		return;
	
	_bstree_destroy(node->left);
	_bstree_destroy(node->right);
	
	free(node);
}
