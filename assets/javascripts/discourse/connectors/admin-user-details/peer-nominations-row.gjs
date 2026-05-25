import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/helpers/d-icon";
import PeerNominationsHistoryModal from "../../components/peer-nominations-history-modal";

// Renders a row mimicking the Edit Badges display-row on the admin user
// details page, with a "View" button that opens a modal listing every
// peer nomination this member has received. Pre-fetches the list on
// construct so the row label can show a useful count ("3 received" vs
// "none yet") and so the modal opens instantly without a second round
// trip.
//
// Visibility: admin-only AND plugin enabled. The outlet
// (admin-user-details) is already an admin-only page, but we double-
// gate as defence in depth in case the outlet ever moves.
export default class PeerNominationsAdminRow extends Component {
  @service modal;

  @tracked grants = [];
  @tracked loading = true;
  @tracked errorMessage = null;

  static shouldRender(args, { siteSettings, currentUser }) {
    if (!siteSettings.peer_nominations_enabled) return false;
    if (!currentUser?.admin) return false;
    if (!args?.model?.id) return false;
    return true;
  }

  constructor() {
    super(...arguments);
    this.fetchGrants();
  }

  get profileUser() {
    return this.args.outletArgs?.model;
  }

  get countLabel() {
    if (this.loading) return "loading…";
    if (this.errorMessage) return "couldn't load";
    const n = this.grants.length;
    if (n === 0) return "none yet";
    if (n === 1) return "1 received";
    return `${n} received`;
  }

  get viewDisabled() {
    return this.loading || this.errorMessage || this.grants.length === 0;
  }

  @action
  async fetchGrants() {
    const userId = this.profileUser?.id;
    if (!userId) {
      this.loading = false;
      return;
    }
    try {
      const data = await ajax(
        `/peer-nominations/admin/users/${userId}/received`
      );
      this.grants = data?.grants || [];
    } catch (err) {
      this.errorMessage =
        err?.jqXHR?.responseJSON?.errors?.[0] ||
        "Could not load peer-nomination history.";
      popupAjaxError(err);
    } finally {
      this.loading = false;
    }
  }

  @action
  openModal() {
    this.modal.show(PeerNominationsHistoryModal, {
      model: {
        profileUser: this.profileUser,
        grants: this.grants,
      },
    });
  }

  <template>
    <div class="display-row peer-nominations-admin-row">
      <div class="field">Peer nominations</div>
      <div class="value">{{this.countLabel}}</div>
      <div class="controls">
        <button
          type="button"
          class="btn btn-default peer-nominations-admin-row__view-btn"
          disabled={{this.viewDisabled}}
          {{on "click" this.openModal}}
        >
          {{dIcon "certificate"}}
          View peer nominations
        </button>
      </div>
    </div>
  </template>
}
