import Component from "@glimmer/component";
import DModal from "discourse/components/d-modal";
import PeerNominationsHistoryPanel from "./peer-nominations-history-panel";

// Admin-only modal showing every approved peer-nomination received by a
// member. Opened from the admin user details page via the
// admin-user-details connector. Grants are pre-fetched by the row
// connector and passed in via @model.grants — the modal stays a pure
// presentational shell.
export default class PeerNominationsHistoryModal extends Component {
  get profileUser() {
    return this.args.model?.profileUser;
  }

  get grants() {
    return this.args.model?.grants || [];
  }

  get title() {
    const name =
      this.profileUser?.name?.trim() ||
      this.profileUser?.username ||
      "this member";
    return `Peer nominations received by ${name}`;
  }

  <template>
    <DModal
      @title={{this.title}}
      @closeModal={{@closeModal}}
      class="peer-nominations-history-modal"
    >
      <:body>
        <PeerNominationsHistoryPanel @grants={{this.grants}} />
      </:body>
    </DModal>
  </template>
}
