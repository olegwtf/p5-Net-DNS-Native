#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pthread.h>

typedef struct {
	HV* fd_set;
	pthread_mutex_t mutex;
} Net_DNS_Native;

MODULE = Net::DNS::Native	PACKAGE = Net::DNS::Native

PROTOTYPES: DISABLE

SV*
new(char* class)
	PREINIT:
		Net_DNS_Native *self;
	CODE:
		Newx(self, 1, Net_DNS_Native);
		self->fd_set = newHV();
		pthread_mutex_init(&self->mutex, NULL);
		
		RETVAL = newSV(0);
		sv_setref_pv(RETVAL, class, (void *)self);
	OUTPUT:
		RETVAL

void
inet_aton(Net_DNS_Native *self, char* host)
	CODE:
		ENTER;
		SAVETMPS;
		
		PUSHMARK(SP);
		XPUSHs(sv_2mortal(newSVpv(host, 0)));
		PUTBACK;
		
		call_pv("Socket::inet_aton", G_DISCARD);
		
		FREETMPS;
		LEAVE;

void
DESTROY(Net_DNS_Native *self)
	CODE:
		SvREFCNT_dec((SV*)self->fd_set);
		pthread_mutex_destroy(&self->mutex);
		Safefree(self);
