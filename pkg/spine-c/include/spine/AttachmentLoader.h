/******************************************************************************
 * Spine Runtimes License Agreement
 * Last updated April 5, 2025. Replaces all prior versions.
 *
 * Copyright (c) 2013-2025, Esoteric Software LLC
 *
 * Integration of the Spine Runtimes into software or otherwise creating
 * derivative works of the Spine Runtimes is permitted under the terms and
 * conditions of Section 2 of the Spine Editor License Agreement:
 * http://esotericsoftware.com/spine-editor-license
 *
 * Otherwise, it is permitted to integrate the Spine Runtimes into software
 * or otherwise create derivative works of the Spine Runtimes (collectively,
 * "Products"), provided that each user of the Products must obtain their own
 * Spine Editor license and redistribution of the Products in any form must
 * include this license and copyright notice.
 *
 * THE SPINE RUNTIMES ARE PROVIDED BY ESOTERIC SOFTWARE LLC "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL ESOTERIC SOFTWARE LLC BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES,
 * BUSINESS INTERRUPTION, OR LOSS OF USE, DATA, OR PROFITS) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THE SPINE RUNTIMES, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *****************************************************************************/

#ifndef SPINE_ATTACHMENTLOADER_H_
#define SPINE_ATTACHMENTLOADER_H_

#include <spine/dll.h>
#include <spine/Attachment.h>
#include <spine/Skin.h>
#include <spine/Sequence.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spAttachmentLoader {
	char *error1;
	char *error2;

	const void *vtable;
} spAttachmentLoader;

SP_API void spAttachmentLoader_dispose(spAttachmentLoader *self);

/* Called to create each attachment. Returns 0 to not load an attachment. If 0 is returned and _spAttachmentLoader_setError was
 * called, an error occurred. */
SP_API spAttachment *
spAttachmentLoader_createAttachment(spAttachmentLoader *self, spSkin *skin, spAttachmentType type, const char *name,
									const char *path, spSequence *sequence);
/* Called after the attachment has been fully configured. */
SP_API void spAttachmentLoader_configureAttachment(spAttachmentLoader *self, spAttachment *attachment);
/* Called just before the attachment is disposed. This can release allocations made in spAttachmentLoader_configureAttachment. */
SP_API void spAttachmentLoader_disposeAttachment(spAttachmentLoader *self, spAttachment *attachment);

#ifdef __cplusplus
}
#endif

#endif /* SPINE_ATTACHMENTLOADER_H_ */
