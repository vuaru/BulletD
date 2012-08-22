/*
Bullet Continuous Collision Detection and Physics Library
Copyright (c) 2003-2006 Erwin Coumans  http://continuousphysics.com/Bullet/

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the use of this software.
Permission is granted to anyone to use this software for any purpose, 
including commercial applications, and to alter it and redistribute it freely, 
subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
*/

//D port of Bullet Physics

module bullet.collision.broadphase.overlappingPairCache;

import bullet.collision.broadphase.broadphaseInterface;
import bullet.collision.broadphase.broadphaseProxy;
import bullet.collision.broadphase.overlappingPairCallback;
import bullet.linearMath.btAlignedObjectArray;

abstract class btOverlapCallback {
	//return true for deletion of the pair
	bool processOverlap()(auto ref btBroadphasePair pair);
}

abstract class btOverlapFilterCallback {
	// return true when pairs need collision
	bool	needBroadphaseCollision(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1) const;
}

int	gOverlappingPairs = 0;

int gRemovePairs =0;
int gAddedPairs =0;
int gFindPairs =0;

immutable int BT_NULL_PAIR = 0xffffffff;

alias btAlignedObjectArray!btBroadphasePair btBroadphasePairArray;

///The btOverlappingPairCache provides an interface for overlapping pair management (add, remove, storage), used by the btBroadphaseInterface broadphases.
///The btHashedOverlappingPairCache and btSortedOverlappingPairCache classes are two implementations.
abstract class btOverlappingPairCache: btOverlappingPairCallback {
public:
	//Is this still needed in D?
	~this() {} // this is needed so we can get to the derived class destructor

	btBroadphasePair* getOverlappingPairArrayPtr();
	
	const btBroadphasePair*	getOverlappingPairArrayPtr() const;

	ref btBroadphasePairArray getOverlappingPairArray();

	void cleanOverlappingPair()(auto ref btBroadphasePair pair,btDispatcher* dispatcher);

	int getNumOverlappingPairs() const;

	void cleanProxyFromPairs(btBroadphaseProxy* proxy, btDispatcher* dispatcher);

	void setOverlapFilterCallback(btOverlapFilterCallback* callback);

	void processAllOverlappingPairs(btOverlapCallback*, btDispatcher* dispatcher);

	btBroadphasePair* findPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1);

	bool hasDeferredRemoval();

	void setInternalGhostPairCallback(btOverlappingPairCallback* ghostPairCallback);

	void sortOverlappingPairs(btDispatcher* dispatcher);

};

/// Hash-space based Pair Cache, thanks to Erin Catto, Box2D, http://www.box2d.org, and Pierre Terdiman, Codercorner, http://codercorner.com
class btHashedOverlappingPairCache: btOverlappingPairCache {
	btBroadphasePairArray	m_overlappingPairArray;
	btOverlapFilterCallback* m_overlapFilterCallback;
	bool m_blockedForChanges;


public:
	this();
	~this();

	
	void removeOverlappingPairsContainingProxy(btBroadphaseProxy* proxy,btDispatcher* dispatcher);

	void*	removeOverlappingPair(btBroadphaseProxy* proxy0,btBroadphaseProxy* proxy1,btDispatcher* dispatcher);
	
	bool needsBroadphaseCollision(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1) const {
		if (m_overlapFilterCallback)
			return m_overlapFilterCallback.needBroadphaseCollision(proxy0,proxy1);

		bool collides = (proxy0.m_collisionFilterGroup & proxy1.m_collisionFilterMask) != 0;
		collides = collides && (proxy1.m_collisionFilterGroup & proxy0.m_collisionFilterMask);
		
		return collides;
	}

	// Add a pair and return the new pair. If the pair already exists,
	// no new pair is created and the old one is returned.
	btBroadphasePair*  addOverlappingPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1) {
		gAddedPairs++;

		if (!needsBroadphaseCollision(proxy0,proxy1))
			return 0;

		return internalAddPair(proxy0, proxy1);
	}

	

	void cleanProxyFromPairs(btBroadphaseProxy* proxy, btDispatcher* dispatcher);

	
	void processAllOverlappingPairs(btOverlapCallback*,btDispatcher* dispatcher);

	btBroadphasePair*	getOverlappingPairArrayPtr() {
		return &m_overlappingPairArray[0];
	}

	const btBroadphasePair*	getOverlappingPairArrayPtr() const {
		return &m_overlappingPairArray[0];
	}

	ref btBroadphasePairArray	getOverlappingPairArray() {
		return m_overlappingPairArray;
	}

	const ref btBroadphasePairArray	getOverlappingPairArray() const {
		return m_overlappingPairArray;
	}

	void cleanOverlappingPair()(auto ref btBroadphasePair pair, btDispatcher* dispatcher);



	btBroadphasePair* findPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1);

	int GetCount() const { return m_overlappingPairArray.size(); }
//	btBroadphasePair* GetPairs() { return m_pairs; }

	btOverlapFilterCallback* getOverlapFilterCallback() {
		return m_overlapFilterCallback;
	}

	void setOverlapFilterCallback(btOverlapFilterCallback* callback) {
		m_overlapFilterCallback = callback;
	}

	int	getNumOverlappingPairs() const {
		return m_overlappingPairArray.size();
	}
private:
	
	btBroadphasePair* 	internalAddPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1);

	void growTables();

	bool equalsPair()(const auto ref btBroadphasePair pair, int proxyId1, int proxyId2) {	
		return pair.m_pProxy0.getUid() == proxyId1 && pair.m_pProxy1.getUid() == proxyId2;
	}

	/*
	// Thomas Wang's hash, see: http://www.concentric.net/~Ttwang/tech/inthash.htm
	// This assumes proxyId1 and proxyId2 are 16-bit.
	SIMD_FORCE_INLINE int getHash(int proxyId1, int proxyId2)
	{
		int key = (proxyId2 << 16) | proxyId1;
		key = ~key + (key << 15);
		key = key ^ (key >> 12);
		key = key + (key << 2);
		key = key ^ (key >> 4);
		key = key * 2057;
		key = key ^ (key >> 16);
		return key;
	}
	*/

	uint getHash(uint proxyId1, uint proxyId2) {
		int key = cast(int)((cast(uint)proxyId1) | ((cast(uint)proxyId2) << 16));
		// Thomas Wang's hash

		key += ~(key << 15);
		key ^=  (key >> 10);
		key +=  (key << 3);
		key ^=  (key >> 6);
		key += ~(key << 11);
		key ^=  (key >> 16);
		return cast(uint)(key);
	}
	




	btBroadphasePair* internalFindPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1, int hash) {
		int proxyId1 = proxy0.getUid();
		int proxyId2 = proxy1.getUid();
		
		version(none) { // wrong, 'equalsPair' use unsorted uids, copy-past devil striked again. Nat.
			if (proxyId1 > proxyId2) 
				btSwap(proxyId1, proxyId2);
		}

		int index = m_hashTable[hash];
		
		while( index != BT_NULL_PAIR && equalsPair(m_overlappingPairArray[index], proxyId1, proxyId2) == false) {
			index = m_next[index];
		}

		if (index == BT_NULL_PAIR) {
			return NULL;
		}

		btAssert(index < m_overlappingPairArray.size());

		return &m_overlappingPairArray[index];
	}

	bool	hasDeferredRemoval() {
		return false;
	}

	void setInternalGhostPairCallback(btOverlappingPairCallback* ghostPairCallback) {
		m_ghostPairCallback = ghostPairCallback;
	}

	void sortOverlappingPairs(btDispatcher* dispatcher);
	

protected:
	
	btAlignedObjectArray!int	m_hashTable;
	btAlignedObjectArray!int	m_next;
	btOverlappingPairCallback*	m_ghostPairCallback;
	
};

///btSortedOverlappingPairCache maintains the objects with overlapping AABB
///Typically managed by the Broadphase, Axis3Sweep or btSimpleBroadphase
class btSortedOverlappingPairCache: btOverlappingPairCache {
	protected:
		//avoid brute-force finding all the time
		btBroadphasePairArray	m_overlappingPairArray;

		//during the dispatch, check that user doesn't destroy/create proxy
		bool m_blockedForChanges;

		///by default, do the removal during the pair traversal
		bool m_hasDeferredRemoval;
		
		//if set, use the callback instead of the built in filter in needBroadphaseCollision
		btOverlapFilterCallback* m_overlapFilterCallback;

		btOverlappingPairCallback* m_ghostPairCallback;

	public:
			
		this();	
		~this();

		void processAllOverlappingPairs(btOverlapCallback*,btDispatcher* dispatcher);

		void* removeOverlappingPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1,btDispatcher* dispatcher);

		void cleanOverlappingPair()(auto ref btBroadphasePair pair, btDispatcher* dispatcher);
		
		btBroadphasePair* addOverlappingPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1);

		btBroadphasePair* findPair(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1);
			
		void cleanProxyFromPairs(btBroadphaseProxy* proxy, btDispatcher* dispatcher);

		void removeOverlappingPairsContainingProxy(btBroadphaseProxy* proxy, btDispatcher* dispatcher);


		bool needsBroadphaseCollision(btBroadphaseProxy* proxy0, btBroadphaseProxy* proxy1) const {
			if (m_overlapFilterCallback)
				return m_overlapFilterCallback.needBroadphaseCollision(proxy0,proxy1);

			bool collides = (proxy0.m_collisionFilterGroup & proxy1.m_collisionFilterMask) != 0;
			collides = collides && (proxy1.m_collisionFilterGroup & proxy0.m_collisionFilterMask);
			
			return collides;
		}
		
		ref btBroadphasePairArray getOverlappingPairArray() {
			return m_overlappingPairArray;
		}

		const ref btBroadphasePairArray getOverlappingPairArray() const {
			return m_overlappingPairArray;
		}

		


		btBroadphasePair*	getOverlappingPairArrayPtr() {
			return &m_overlappingPairArray[0];
		}

		const btBroadphasePair*	getOverlappingPairArrayPtr() const {
			return &m_overlappingPairArray[0];
		}

		int	getNumOverlappingPairs() const {
			return m_overlappingPairArray.size();
		}
		
		btOverlapFilterCallback* getOverlapFilterCallback() {
			return m_overlapFilterCallback;
		}

		void setOverlapFilterCallback(btOverlapFilterCallback* callback) {
			m_overlapFilterCallback = callback;
		}

		bool hasDeferredRemoval() {
			return m_hasDeferredRemoval;
		}

		void setInternalGhostPairCallback(btOverlappingPairCallback* ghostPairCallback) {
			m_ghostPairCallback = ghostPairCallback;
		}

		void sortOverlappingPairs(btDispatcher* dispatcher);
		
};

///btNullPairCache skips add/removal of overlapping pairs. Userful for benchmarking and unit testing.
class btNullPairCache: btOverlappingPairCache {
private:
	btBroadphasePairArray	m_overlappingPairArray;

public:

	btBroadphasePair* getOverlappingPairArrayPtr() {
		return &m_overlappingPairArray[0];
	}
	const btBroadphasePair*	getOverlappingPairArrayPtr() const {
		return &m_overlappingPairArray[0];
	}
	ref btBroadphasePairArray getOverlappingPairArray() {
		return m_overlappingPairArray;
	}
	
	void cleanOverlappingPair()(auto ref btBroadphasePair /*pair*/, btDispatcher* /*dispatcher*/) {
		
	}

	int getNumOverlappingPairs() const {
		return 0;
	}

	void	cleanProxyFromPairs(btBroadphaseProxy* /*proxy*/, btDispatcher* /*dispatcher*/) {

	}

	void setOverlapFilterCallback(btOverlapFilterCallback* /*callback*/) {
		
	}

	void processAllOverlappingPairs(btOverlapCallback*, btDispatcher* /*dispatcher*/) {
	}

	btBroadphasePair* findPair(btBroadphaseProxy* /*proxy0*/, btBroadphaseProxy* /*proxy1*/) {
		return null;
	}

	bool hasDeferredRemoval() {
		return true;
	}

	void setInternalGhostPairCallback(btOverlappingPairCallback* /* ghostPairCallback */) {

	}

	btBroadphasePair* addOverlappingPair(btBroadphaseProxy* /*proxy0*/, btBroadphaseProxy* /*proxy1*/) {
		return null;
	}

	void* removeOverlappingPair(btBroadphaseProxy* /*proxy0*/,btBroadphaseProxy* /*proxy1*/, btDispatcher* /*dispatcher*/) {
		return null;
	}

	void removeOverlappingPairsContainingProxy(btBroadphaseProxy* /*proxy0*/, btDispatcher* /*dispatcher*/) {
		
	}
	
	void sortOverlappingPairs(btDispatcher* dispatcher) {
        cast(void) dispatcher;
	}

};