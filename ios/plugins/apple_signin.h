/**************************************************************************/
/*  apple_signin.h                                                        */
/**************************************************************************/
/* Copyright (c) 2025-present Vertex Ludi LTDA                            */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#ifndef GODOT_APPLE_SIGNIN_H
#define GODOT_APPLE_SIGNIN_H

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/string/ustring.h"

#ifdef __OBJC__
@import AuthenticationServices;
#import "apple_signin_delegate.h"
#endif

class GodotAppleSignIn : public RefCounted {
	
	GDCLASS(GodotAppleSignIn, RefCounted);
	
	static void _bind_methods();
	
#ifdef __OBJC__
	GodotASAuthorizationControllerDelegate *signInDelegate = nil;
#endif
	
public:
	void initiate_signin();
	void request_credential_state(const String &userId);
	
	void auth_callback(const Dictionary &data);
	void auth_failed_callback(const String &error);
	
	GodotAppleSignIn();
	~GodotAppleSignIn();
};



#endif
