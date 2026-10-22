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

/** `reports/{reportId}`（投稿の報告。F-14） */
export function reportRef(db: Firestore, reportId: string): DocumentReference {
  return db.collection("reports").doc(reportId);
}

/** `mail/{mailId}`（Trigger Email 拡張（firestore-send-email）が読んで送るメール。拡張の `MAIL_COLLECTION`） */
export function mailRef(db: Firestore, mailId: string): DocumentReference {
  return db.collection("mail").doc(mailId);
}
