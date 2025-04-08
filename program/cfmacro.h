#ifndef CFMACRO_H
#define CFMACRO_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h> // For potential error logging if desired

/**
 * @brief Safely gets a numeric value from a CFDictionary.
 *
 * Retrieves the CFTypeRef associated with 'key' from 'dict'.
 * Checks if it's a non-NULL CFNumberRef.
 * If yes, attempts to get its value as the specified 'numType' and assigns it to 'var'.
 * If the key doesn't exist, the value is not a CFNumber, or CFNumberGetValue fails,
 * 'var' might remain uninitialized or unchanged (depending on its previous state).
 * The caller should check the value of 'var' afterwards if validation is needed.
 *
 * @param dict The CFDictionaryRef to query.
 * @param key The key (const void *, typically a CFStringRef) for the desired value.
 * @param numType The expected CFNumberType (e.g., kCFNumberIntType, kCFNumberCGFloatType).
 * @param var The variable (passed by address implicitly via &var in the macro usage)
 * to store the extracted numeric value. It must match the type implied by numType.
 */
#define CFDICT_GET_NUM_RET(dict, key, numType, var) \
    do { \
        CFTypeRef _obj = CFDictionaryGetValue((dict), (key)); \
        if (_obj != NULL && CFGetTypeID(_obj) == CFNumberGetTypeID()) { \
            /* Attempt to get the number value. Note: CFNumberGetValue returns Boolean. */ \
            /* We are ignoring the return value here based on observed usage, */ \
            /* assuming the caller checks the 'var' value later. */ \
            CFNumberGetValue((CFNumberRef)_obj, (numType), &(var)); \
        } else { \
            /* Optional: Handle error case, e.g., set var to a default? */ \
            /* fprintf(stderr, "Warning: Key not found or not a CFNumber for %s\n", CFStringGetCStringPtr((CFStringRef)key, kCFStringEncodingUTF8) ?: "Unknown Key"); */ \
            /* Or leave 'var' as is, relying on caller checks like 'pid <= 0' */ \
        } \
    } while (0)

#endif // CFMACRO_H

static inline CFArrayRef CFNumberArrayMake(void *values, size_t size, int count, CFNumberType type) {
    CFNumberRef temp[count];
  
    for (int i = 0; i < count; ++i) {
        temp[i] = CFNumberCreate(NULL, type, ((char *)values) + (size * i));
    }
  
    CFArrayRef result = CFArrayCreate(NULL, (const void **)temp, count, &kCFTypeArrayCallBacks);
  
    for (int i = 0; i < count; ++i) {
        CFRelease(temp[i]);
    }
  
    return result;
  }