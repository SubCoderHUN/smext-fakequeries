/**
 * Minimal SteamWorks HTTP Include
 *
 * Only the HTTP functions needed for webhook requests.
 * Drop-in replacement to avoid SteamWorks.inc line 282 compile error.
 * Works with #pragma newdecls required (transitional syntax).
 *
 * Requires: SteamWorks extension (.dll/.so) installed on server.
 *   https://github.com/KyleSanderson/SteamWorks
 */

#if defined _steamworks_http_included
#endinput
#endif
#define _steamworks_http_included

enum EHTTPMethod
{
	k_EHTTPMethodInvalid = 0,
	k_EHTTPMethodGET = 1,
	k_EHTTPMethodHEAD = 2,
	k_EHTTPMethodPOST = 3,
	k_EHTTPMethodPUT = 4,
	k_EHTTPMethodDELETE = 5,
	k_EHTTPMethodOPTIONS = 6,
	k_EHTTPMethodPATCH = 7
};

enum EHTTPStatusCode
{
	k_EHTTPStatusCodeInvalid = 0,
	k_EHTTPStatusCode200OK = 200,
	k_EHTTPStatusCode201Created = 201,
	k_EHTTPStatusCode202Accepted = 202,
	k_EHTTPStatusCode204NoContent = 204,
	k_EHTTPStatusCode301MovedPermanently = 301,
	k_EHTTPStatusCode302Found = 302,
	k_EHTTPStatusCode304NotModified = 304,
	k_EHTTPStatusCode400BadRequest = 400,
	k_EHTTPStatusCode401Unauthorized = 401,
	k_EHTTPStatusCode403Forbidden = 403,
	k_EHTTPStatusCode404NotFound = 404,
	k_EHTTPStatusCode405MethodNotAllowed = 405,
	k_EHTTPStatusCode408RequestTimeout = 408,
	k_EHTTPStatusCode429TooManyRequests = 429,
	k_EHTTPStatusCode500InternalServerError = 500,
	k_EHTTPStatusCode502BadGateway = 502,
	k_EHTTPStatusCode503ServiceUnavailable = 503
};

typedef SteamWorksHTTPRequestCompleted = function int (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode);
typedef SteamWorksHTTPHeadersReceived = function int (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode);
typedef SteamWorksHTTPDataReceived = function int (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int iOffset, int iBytesReceived);
typedef SteamWorksHTTPBodyCallback = function int (const char[] sData);

native Handle SteamWorks_CreateHTTPRequest(EHTTPMethod eHTTPRequestMethod, const char[] sAbsoluteURL);
native bool SteamWorks_SetHTTPRequestHeaderValue(Handle hRequest, const char[] sHeaderName, const char[] sHeaderValue);
native bool SteamWorks_SetHTTPRequestRawPostBody(Handle hRequest, const char[] sContentType, const char[] sBody, int iBodyLen);
native bool SteamWorks_SetHTTPCallbacks(Handle hRequest, SteamWorksHTTPRequestCompleted fCompleted = INVALID_FUNCTION, SteamWorksHTTPHeadersReceived fHeaders = INVALID_FUNCTION, SteamWorksHTTPDataReceived fData = INVALID_FUNCTION);
native bool SteamWorks_SendHTTPRequest(Handle hRequest);
native bool SteamWorks_GetHTTPResponseBodySize(Handle hRequest, int &iBody);
native bool SteamWorks_GetHTTPResponseBodyData(Handle hRequest, char[] sBody, int iLength);
native bool SteamWorks_GetHTTPResponseBodyCallback(Handle hRequest, SteamWorksHTTPBodyCallback fCallback);

public Extension __ext_SteamWorks =
{
	name = "SteamWorks",
	file = "SteamWorks.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};
