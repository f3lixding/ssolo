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

#ifndef SPINE_IKCONSTRAINT_H_
#define SPINE_IKCONSTRAINT_H_

#include <spine/dll.h>
#include <spine/IkConstraintData.h>
#include <spine/Bone.h>

#ifdef __cplusplus
extern "C" {
#endif

struct spSkeleton;

typedef struct spIkConstraint {
	spIkConstraintData *data;

	int bonesCount;
	spBone **bones;

	spBone *target;
	int bendDirection;
	int /*boolean*/ compress;
	int /*boolean*/ stretch;
	float mix;
	float softness;

	int /*boolean*/ active;
} spIkConstraint;

SP_API spIkConstraint *spIkConstraint_create(spIkConstraintData *data, const struct spSkeleton *skeleton);

SP_API void spIkConstraint_dispose(spIkConstraint *self);

SP_API void spIkConstraint_update(spIkConstraint *self);

SP_API void spIkConstraint_setToSetupPose(spIkConstraint *self);

SP_API void
spIkConstraint_apply1(spBone *bone, float targetX, float targetY, int /*boolean*/ compress, int /*boolean*/ stretch,
					  int /*boolean*/ uniform, float alpha);

SP_API void spIkConstraint_apply2(spBone *parent, spBone *child, float targetX, float targetY, int bendDirection,
								  int /*boolean*/ stretch, int /*boolean*/ uniform, float softness, float alpha);

#ifdef __cplusplus
}
#endif

#endif /* SPINE_IKCONSTRAINT_H_ */
