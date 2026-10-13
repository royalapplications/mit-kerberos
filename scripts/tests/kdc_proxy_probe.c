#include <krb5.h>
#include <stdio.h>

/* The local HTTPS fixture returns this error instead of issuing credentials.
 * Receiving it proves that both the HTTPS request and KKDCP reply worked. */
int main(void)
{
    krb5_context context = NULL;
    krb5_principal principal = NULL;
    krb5_creds creds = {0};
    krb5_error_code ret;

    ret = krb5_init_context(&context);
    if (ret != 0)
        return 2;
    ret = krb5_parse_name(context, "probe@KDC-PROXY.TEST", &principal);
    if (ret == 0) {
        ret = krb5_get_init_creds_password(context, &creds, principal,
                                         "unused-test-password", NULL, NULL,
                                         0, NULL, NULL);
    }
    if (ret != KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN) {
        const char *message = krb5_get_error_message(context, ret);
        fprintf(stderr, "Unexpected Kerberos result: %s (%ld)\n", message,
                (long)ret);
        krb5_free_error_message(context, message);
    }
    krb5_free_cred_contents(context, &creds);
    krb5_free_principal(context, principal);
    krb5_free_context(context);
    return ret == KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN ? 0 : 1;
}
