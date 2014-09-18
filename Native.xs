#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pthread.h>
#include <string.h>

typedef struct {
	HV* fd_set;
	pthread_mutex_t mutex;
	pthread_attr_t thread_attrs;
} Net_DNS_Native;

struct thread_arg {
	Net_DNS_Native *self;
	char *host;
};

/*
void *_start_inet_aton(void *arg) {
	_inet_aton(arg);
}
*/
void *_inet_aton(void *v_arg) {
	struct thread_arg *arg = (struct thread_arg *)v_arg;
	
	dSP;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(arg->host, 0)));
	PUTBACK;
	
	call_pv("Socket::inet_aton", G_DISCARD);
	
	FREETMPS;
	LEAVE;
	
	free(arg->host);
	free(arg);
}

MODULE = Net::DNS::Native	PACKAGE = Net::DNS::Native

PROTOTYPES: DISABLE

SV*
new(char* class)
	PREINIT:
		Net_DNS_Native *self;
	CODE:
		Newx(self, 1, Net_DNS_Native);
		self->fd_set = newHV();
		pthread_attr_init(&self->thread_attrs);
		pthread_attr_setdetachstate(&self->thread_attrs, PTHREAD_CREATE_DETACHED);
		pthread_mutex_init(&self->mutex, NULL);
		
		RETVAL = newSV(0);
		sv_setref_pv(RETVAL, class, (void *)self);
	OUTPUT:
		RETVAL

void
inet_aton(Net_DNS_Native *self, char *host)
	CODE:
		pthread_t tid;
		struct thread_arg *t_arg = malloc(sizeof(struct thread_arg));
		t_arg->self = self;
		t_arg->host = strdup(host);
		pthread_create(&tid, &self->thread_attrs, _inet_aton, (void *)t_arg);

void
DESTROY(Net_DNS_Native *self)
	CODE:
		SvREFCNT_dec((SV*)self->fd_set);
		pthread_attr_destroy(&self->thread_attrs);
		pthread_mutex_destroy(&self->mutex);
		Safefree(self);
