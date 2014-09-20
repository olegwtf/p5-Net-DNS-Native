#include <pthread.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "bstree.h"

typedef struct {
	pthread_mutex_t mutex;
	pthread_attr_t thread_attrs;
	bstree* fd_map;
} Net_DNS_Native;

typedef struct {
	Net_DNS_Native *self;
	char *host;
	int fd0;
} DNS_thread_arg;

typedef struct {
	int fd1;
	char *ip;
	int ip_len;
} DNS_result;

void *_inet_aton(void *v_arg) {
	DNS_thread_arg *arg = (DNS_thread_arg *)v_arg;
	
	printf("gethostbyname started at %d\n", time(NULL));
	struct hostent *rslv = gethostbyname(arg->host);
	printf("gethostbyname finished at %d\n", time(NULL));
	
	pthread_mutex_lock(&arg->self->mutex);
	DNS_result *res = bstree_get(arg->self->fd_map, arg->fd0);
	
	if (rslv && rslv->h_addrtype == AF_INET && rslv->h_length == 4) {
		res->ip = malloc(rslv->h_length*sizeof(char));
		memcpy(res->ip, rslv->h_addr, res->ip_len=rslv->h_length);
	}
	
	pthread_mutex_unlock(&arg->self->mutex);
	
	free(arg->host);
	free(arg);
	write(res->fd1, "\1", 1);
}

MODULE = Net::DNS::Native	PACKAGE = Net::DNS::Native

PROTOTYPES: DISABLE

SV*
new(char* class)
	PREINIT:
		Net_DNS_Native *self;
	CODE:
		Newx(self, 1, Net_DNS_Native);
		pthread_attr_init(&self->thread_attrs);
		pthread_attr_setdetachstate(&self->thread_attrs, PTHREAD_CREATE_DETACHED);
		pthread_mutex_init(&self->mutex, NULL);
		self->fd_map = bstree_new();
		
		RETVAL = newSV(0);
		sv_setref_pv(RETVAL, class, (void *)self);
	OUTPUT:
		RETVAL

int
inet_aton_fd(Net_DNS_Native *self, char *host)
	INIT:
		int fd[2];
	CODE:
		socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC, fd);
		
		DNS_result *res = malloc(sizeof(DNS_result));
		res->fd1    = fd[1];
		res->ip     = NULL;
		res->ip_len = 0;
		pthread_mutex_lock(&self->mutex);
		bstree_put(self->fd_map, fd[0], res);
		pthread_mutex_unlock(&self->mutex);
		
		pthread_t tid;
		DNS_thread_arg *t_arg = malloc(sizeof(DNS_thread_arg));
		t_arg->self = self;
		t_arg->host = strdup(host);
		t_arg->fd0  = fd[0];
		pthread_create(&tid, &self->thread_attrs, _inet_aton, (void *)t_arg);
		
		RETVAL = fd[0];
	OUTPUT:
		RETVAL

void
get_result_fd(Net_DNS_Native *self, int fd)
	PPCODE:
		pthread_mutex_lock(&self->mutex);
		DNS_result *res = bstree_get(self->fd_map, fd);
		pthread_mutex_unlock(&self->mutex);
		
		XPUSHs(sv_2mortal(newSVpvn(res->ip, res->ip_len)));
		close(fd);
		close(res->fd1);
		free(res->ip);
		free(res);

void
DESTROY(Net_DNS_Native *self)
	CODE:
		pthread_attr_destroy(&self->thread_attrs);
		pthread_mutex_destroy(&self->mutex);
		bstree_destroy(self->fd_map);
		Safefree(self);
