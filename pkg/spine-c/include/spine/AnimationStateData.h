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

#ifndef SPINE_ANIMATIONSTATEDATA_H_
#define SPINE_ANIMATIONSTATEDATA_H_

#include <spine/dll.h>
#include <spine/Animation.h>
#include <spine/SkeletonData.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct spAnimationStateData {
	spSkeletonData *skeletonData;
	float defaultMix;
	const void *entries;
} spAnimationStateData;

SP_API spAnimationStateData *spAnimationStateData_create(spSkeletonData *skeletonData);

SP_API void spAnimationStateData_dispose(spAnimationStateData *self);

SP_API void
spAnimationStateData_setMixByName(spAnimationStateData *self, const char *fromName, const char *toName, float duration);

SP_API void spAnimationStateData_setMix(spAnimationStateData *self, spAnimation *from, spAnimation *to, float duration);
/* Returns 0 if there is no mixing between the animations. */
SP_API float spAnimationStateData_getMix(spAnimationStateData *self, spAnimation *from, spAnimation *to);

#ifdef __cplusplus
}
#endif

#endif /* SPINE_ANIMATIONSTATEDATA_H_ */
