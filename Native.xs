#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pthread.h>
#include <string.h>
#include <netdb.h>
#include "bstree.h"

typedef struct {
	pthread_mutex_t mutex;
	pthread_attr_t thread_attrs;
	SV* const_af_unix;
	SV* const_sock_stream;
	SV* const_pf_unspec;
	bstree* fd_map;
} Net_DNS_Native;

typedef struct {
	Net_DNS_Native *self;
	char *host;
	int fd1;
} DNS_thread_arg;

typedef struct {
	int fd2;
	SV* sock2;
	char *ip;
} DNS_result;

void *_inet_aton(void *v_arg) {
	DNS_thread_arg *arg = (DNS_thread_arg *)v_arg;
	
	struct hostent *rslv = gethostbyname(arg->host);
	
	pthread_mutex_lock(&arg->self->mutex);
	DNS_result *res = bstree_get(arg->self->fd_map, arg->fd1);
	
	if (rslv && rslv->h_addrtype == AF_INET && rslv->h_length == 4) {
		//rv = newSVpvn((char *)rslv->h_addr, rslv->h_length);
		res->ip = rslv->h_addr;
	}
	else {
		
	}
	
	pthread_mutex_unlock(&arg->self->mutex);
	
	free(arg->host);
	free(arg);
	write(res->fd2, "\1", 1);
}

SV* _get_perl_constant(char *name) {
	dSP;
	SV* rv;
	
	PUSHMARK(SP);
	int count = call_pv(name, G_SCALAR|G_NOARGS);
	SPAGAIN;
	
	if (count != 1) {
		croak("More than one value returned by constant `%s'", name);
	}
	
	rv = POPs;
	PUTBACK;
	
	return rv;
}

int _get_perl_handle_fd(SV *hdl) {
	dSP;
	int rv;
	
	PUSHMARK(SP);
	XPUSHs(hdl);
	PUTBACK;
	
	int count = call_pv("CORE::fileno", G_SCALAR);
	
	SPAGAIN;
	if (count != 1)
		croak("fileno() returned more than one value");
	
	rv = POPi;
	PUTBACK;
	
	return rv;
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
		
		self->const_af_unix     = _get_perl_constant("Socket::AF_UNIX");
		self->const_sock_stream = _get_perl_constant("Socket::SOCK_STREAM");
		self->const_pf_unspec   = _get_perl_constant("Socket::PF_UNSPEC");
		
		self->fd_map = bstree_new();
		
		RETVAL = newSV(0);
		sv_setref_pv(RETVAL, class, (void *)self);
	OUTPUT:
		RETVAL

SV*
inet_aton(Net_DNS_Native *self, char *host)
	INIT:
		SV* sock1 = newSV(0);
		SV* sock2 = newSV(0);
	CODE:
		PUSHMARK(SP);
		XPUSHs(sock1);
		XPUSHs(sock2);
		XPUSHs(self->const_af_unix);
		XPUSHs(self->const_sock_stream);
		XPUSHs(self->const_pf_unspec);
		PUTBACK;
		
		int count = call_pv("CORE::socketpair", G_SCALAR);
		
		SPAGAIN;
		if (count != 1)
			croak("socketpair() returned more than one value");
		
		POPi;
		PUTBACK;
		
		DNS_result *res = malloc(sizeof(DNS_result));
		res->fd2   = _get_perl_handle_fd(sock2);
		res->sock2 = sock2;
		res->ip    = NULL;
		pthread_mutex_lock(&self->mutex);
		int fd1 = _get_perl_handle_fd(sock1);
		bstree_put(self->fd_map, fd1, res);
		pthread_mutex_unlock(&self->mutex);
		
		pthread_t tid;
		DNS_thread_arg *t_arg = malloc(sizeof(DNS_thread_arg));
		t_arg->self = self;
		t_arg->host = strdup(host);
		t_arg->fd1  = fd1;
		pthread_create(&tid, &self->thread_attrs, _inet_aton, (void *)t_arg);
		
		RETVAL = sock1;
	OUTPUT:
		RETVAL

void
DESTROY(Net_DNS_Native *self)
	CODE:
		pthread_attr_destroy(&self->thread_attrs);
		pthread_mutex_destroy(&self->mutex);
		bstree_destroy(self->fd_map);
		Safefree(self);
