/**
 * Firestore のドキュメントの参照（05 の §3 のパス）。パスの文字列を 1 か所にまとめる。
 */
import type { CollectionReference, DocumentReference, Firestore } from "firebase-admin/firestore";

/** `users/{uid}` */
export function userRef(db: Firestore, uid: string): DocumentReference {
  return db.collection("users").doc(uid);
}

/** `rooms/{roomId}` */
export function roomRef(db: Firestore, roomId: string): DocumentReference {
  return db.collection("rooms").doc(roomId);
}

/** `rooms/{roomId}/members` */
export function membersRef(room: DocumentReference): CollectionReference {
  return room.collection("members");
}

/** `rooms/{roomId}/candidates` */
export function candidatesRef(room: DocumentReference): CollectionReference {
  return room.collection("candidates");
}

/** `rooms/{roomId}/draws` */
export function drawsRef(room: DocumentReference): CollectionReference {
  return room.collection("draws");
}

/** `inviteCodes/{code}` */
export function inviteCodeRef(db: Firestore, code: string): DocumentReference {
  return db.collection("inviteCodes").doc(code);
}
