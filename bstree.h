/* Binary Search Tree implementation */
#include <stdlib.h>

typedef struct bstree_node bstree_node;

struct bstree_node {
	int key;
	void *val;
	struct bstree_node *left;
	struct bstree_node *right;
};

typedef struct {
	bstree_node *root;
	int size;
} bstree;

void bstree_put(bstree *tree, int key, void *val);
void* bstree_get(bstree *tree, int key);
void bstree_del(bstree *tree, int key);
void bstree_destroy(bstree *tree);
int bstree_size(bstree *tree);
bstree_node* _bstree_new_node(int key, void *val);
int _bstree_put(bstree_node *node, int key, void *val);
void* _bstree_get(bstree_node *node, int key);
int _bstree_del(bstree *tree, bstree_node *parent, bstree_node *node, int key);
bstree_node* _bstree_most_left_node_parent(bstree_node *parent, bstree_node *node);
void _bstree_destroy(bstree_node *node);

// PUBLIC API

bstree* bstree_new() {
	bstree *tree = malloc(sizeof(bstree));
	tree->size = 0;
	tree->root = NULL;
	
	return tree;
}

void bstree_put(bstree *tree, int key, void *val) {
	tree->size += _bstree_put(tree->root, key, val);
}

void* bstree_get(bstree *tree, int key) {
	return _bstree_get(tree->root, key);
}

void bstree_del(bstree *tree, int key) {
	tree->size -= _bstree_del(tree, NULL, tree->root, key);
}

void bstree_destroy(bstree *tree) {
	_bstree_destroy(tree->root);
	free(tree);
}

int bstree_size(bstree *tree) {
	return tree->size;
}

// PRIVATE API

bstree_node* _bstree_new_node(int key, void *val) {
	bstree_node *node = malloc(sizeof(bstree_node));
	node->left = node->right = NULL;
	node->key = key;
	node->val = val;
	
	return node;
}

int _bstree_put(bstree_node *node, int key, void *val) {
	if (node == NULL) {
		node = _bstree_new_node(key, val);
		return 1;
	}
	
	if (key > node->key)
		return _bstree_put(node->right, key, val);
	
	if (key < node->key)
		return _bstree_put(node->left, key, val);
	
	node->key = key;
	node->val = val;
	return 0;
}

void* _bstree_get(bstree_node *node, int key) {
	if (node == NULL)
		return NULL;
	
	if (key > node->key)
		return _bstree_get(node->right, key);
	
	if (key < node->key)
		_bstree_get(node->left, key);
	
	return node->val;
}

int _bstree_del(bstree *tree, bstree_node *parent, bstree_node *node, int key) {
	if (node == NULL)
		return 0;
	
	if (key > node->key)
		return _bstree_del(tree, node, node->right, key);
	
	if (key < node->key)
		return _bstree_del(tree, node, node->left, key);
	
	if (node->left == NULL && node->right == NULL) {
		if (parent == NULL) {
			tree->root = NULL;
		}
		else if (parent->left == node) {
			parent->left = NULL;
		}
		else {
			parent->right = NULL;
		}
		
		goto RET;
	}
	
	if (node->left == NULL) {
		if (parent == NULL) {
			tree->root = node->right;
		}
		else if (parent->left == node) {
			parent->left = node->right;
		}
		else {
			parent->right = node->right;
		}
		
		goto RET;
	}
	
	if (node->right == NULL) {
		if (parent == NULL) {
			tree->root = node->left;
		}
		else if (parent->left == node) {
			parent->left = node->left;
		}
		else {
			parent->right = node->left;
		}
		
		goto RET;
	}
	
	bstree_node *next_node_parent = _bstree_most_left_node_parent(NULL, node->right);
	bstree_node *next_node = next_node_parent == NULL ? node->right : next_node_parent->left;
	node->key = next_node->key;
	node->val = next_node->val;
	return _bstree_del(tree, next_node_parent ? next_node_parent : node, next_node, next_node->key);
	
	RET:
		free(node);
		return 1;
}

bstree_node* _bstree_most_left_node_parent(bstree_node *parent, bstree_node *node) {
	if (node->left == NULL)
		return parent;
	
	return _bstree_most_left_node_parent(node, node->left);
}

void _bstree_destroy(bstree_node *node) {
	if (node == NULL)
		return;
	
	_bstree_destroy(node->left);
	_bstree_destroy(node->right);
	
	free(node);
}
