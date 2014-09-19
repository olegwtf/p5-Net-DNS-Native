#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pthread.h>
#include <string.h>
#include <netdb.h>

typedef struct {
	pthread_mutex_t mutex;
	pthread_attr_t thread_attrs;
	SV* const_af_unix;
	SV* const_sock_stream;
	SV* const_pf_unspec;
} Net_DNS_Native;

struct thread_arg {
	Net_DNS_Native *self;
	char *host;
};

void *_inet_aton(void *v_arg) {
	struct thread_arg *arg = (struct thread_arg *)v_arg;
	
	struct hostent *rslv = gethostbyname(arg->host);
	if (!rslv) {
		goto RET;
	}
	
	if (rslv->h_addrtype == AF_INET && rslv->h_length == 4) {
		//rv = newSVpvn((char *)rslv->h_addr, rslv->h_length);
	}
	
	RET:
		free(arg->host);
		free(arg);
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
		
		pthread_t tid;
		struct thread_arg *t_arg = malloc(sizeof(struct thread_arg));
		t_arg->self = self;
		t_arg->host = strdup(host);
		pthread_create(&tid, &self->thread_attrs, _inet_aton, (void *)t_arg);
		
		RETVAL = sock1;
	OUTPUT:
		RETVAL

void
DESTROY(Net_DNS_Native *self)
	CODE:
		pthread_attr_destroy(&self->thread_attrs);
		pthread_mutex_destroy(&self->mutex);
		Safefree(self);
